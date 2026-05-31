/**
 * Automated VectorStore Worker Test
 * Run with: node test_worker.js
 */

import puppeteer from 'puppeteer';
import { createServer } from 'http';
import { readFile } from 'fs/promises';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// MIME types
const mimeTypes = {
    '.html': 'text/html',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.wasm': 'application/wasm',
};

// Create server with COOP/COEP headers
const server = createServer(async (req, res) => {
    let filePath = join(__dirname, 'dist', req.url === '/' ? 'test.html' : req.url);

    // Also check in assets
    if (req.url.startsWith('/assets/')) {
        filePath = join(__dirname, 'dist', req.url);
    }

    try {
        const content = await readFile(filePath);
        const ext = extname(filePath);
        res.writeHead(200, {
            'Content-Type': mimeTypes[ext] || 'text/plain',
            'Cross-Origin-Opener-Policy': 'same-origin',
            'Cross-Origin-Embedder-Policy': 'require-corp',
        });
        res.end(content);
    } catch (e) {
        console.error('404:', req.url);
        res.writeHead(404);
        res.end('Not found');
    }
});

// Test HTML
const testHtml = `<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body>
<script type="module">
async function runTests() {
    const results = { pass: [], fail: [] };

    function pass(msg) {
        results.pass.push(msg);
        console.log('✅', msg);
    }

    function fail(msg, err) {
        results.fail.push(msg + ': ' + err);
        console.error('❌', msg, err);
    }

    try {
        // Import module
        await import('./sqlite_vector_store.js');
        await new Promise(r => setTimeout(r, 500));

        if (!window.SQLiteVectorStore) {
            fail('Module load', 'SQLiteVectorStore not on window');
            window.__testResults = results;
            return;
        }
        pass('Module loaded');

        const store = new window.SQLiteVectorStore(null);

        // Test 1: Initialize
        try {
            await store.initialize('test.db');
            pass('Initialize');
        } catch (e) {
            fail('Initialize', e.message);
            window.__testResults = results;
            return;
        }

        // Test 2: Add document
        try {
            const embedding = new Array(768).fill(0).map((_, i) => Math.sin(i * 0.1));
            await store.addDocument('doc1', 'Test content', embedding, null);
            pass('Add document');
        } catch (e) {
            fail('Add document', e.message);
            window.__testResults = results;
            return;
        }

        // Test 3: Get stats
        try {
            const stats = await store.getStats();
            console.log('Stats:', JSON.stringify(stats));
            if (stats && typeof stats.documentCount === 'number' && stats.documentCount === 1) {
                pass('Get stats: ' + stats.documentCount + ' docs');
            } else {
                fail('Get stats', 'Wrong count: ' + JSON.stringify(stats));
            }
        } catch (e) {
            fail('Get stats', e.message);
            window.__testResults = results;
            return;
        }

        // Test 4: Search
        try {
            const queryEmb = new Array(768).fill(0).map((_, i) => Math.sin(i * 0.1));
            const results_search = await store.searchSimilar(queryEmb, 5, 0.0);
            console.log('Search:', JSON.stringify(results_search));
            if (Array.isArray(results_search) && results_search.length === 1) {
                pass('Search: similarity=' + results_search[0].similarity.toFixed(4));
            } else {
                fail('Search', 'Wrong results: ' + JSON.stringify(results_search));
            }
        } catch (e) {
            fail('Search', e.message);
            window.__testResults = results;
            return;
        }

        // Test 5: Clear
        try {
            await store.clear();
            const stats = await store.getStats();
            if (stats.documentCount === 0) {
                pass('Clear');
            } else {
                fail('Clear', 'Not cleared: ' + stats.documentCount);
            }
        } catch (e) {
            fail('Clear', e.message);
        }

        // Test 6: Close
        try {
            await store.close();
            pass('Close');
        } catch (e) {
            fail('Close', e.message);
        }

    } catch (e) {
        fail('Unexpected', e.message);
    }

    window.__testResults = results;
}

runTests();
</script>
</body>
</html>`;

// Write test HTML
import { writeFile } from 'fs/promises';
await writeFile(join(__dirname, 'dist', 'test.html'), testHtml);

// Start server
const PORT = 3456;
server.listen(PORT, async () => {
    console.log(`Server running at http://localhost:${PORT}`);

    // Launch browser
    const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox']
    });

    const page = await browser.newPage();

    // Capture console
    page.on('console', msg => {
        const text = msg.text();
        if (text.includes('✅')) {
            console.log('\x1b[32m%s\x1b[0m', text);
        } else if (text.includes('❌')) {
            console.log('\x1b[31m%s\x1b[0m', text);
        } else {
            console.log(text);
        }
    });

    page.on('pageerror', err => {
        console.log('\x1b[31mPage error:\x1b[0m', err.message);
    });

    try {
        await page.goto(`http://localhost:${PORT}/test.html`, {
            waitUntil: 'networkidle0',
            timeout: 30000
        });

        // Wait for tests to complete
        await page.waitForFunction(() => window.__testResults, { timeout: 20000 });

        const results = await page.evaluate(() => window.__testResults);

        console.log('\n========================================');
        console.log(`\x1b[32mPassed: ${results.pass.length}\x1b[0m`);
        console.log(`\x1b[31mFailed: ${results.fail.length}\x1b[0m`);

        if (results.fail.length > 0) {
            console.log('\nFailures:');
            results.fail.forEach(f => console.log('\x1b[31m  - %s\x1b[0m', f));
        }
        console.log('========================================\n');

        process.exit(results.fail.length > 0 ? 1 : 0);

    } catch (e) {
        console.error('\x1b[31mTest error:\x1b[0m', e.message);
        process.exit(1);
    } finally {
        await browser.close();
        server.close();
    }
});
