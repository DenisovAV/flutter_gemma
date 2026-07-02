/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

// Server-specific Jaspr import.
import 'package:jaspr/dom.dart' show Color;
import 'package:jaspr/server.dart';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/code_block.dart';
import 'package:jaspr_content/components/github_button.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'components/clicker.dart';
import 'landing/landing_page.dart';
import 'seo.dart';
import 'theme/brand.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

const String _landingDescription =
    'Run Gemma and other LLMs on-device in your Flutter app — '
    'Android, iOS, Web, and Desktop. Multimodal vision & audio, '
    'function calling, on-device agent skills, thinking mode, '
    'GPU acceleration, embeddings, and RAG.';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // [ContentApp.custom] lets us serve a hand-built marketing landing page at `/`
  // alongside the markdown-driven docs under `/docs/*`. The docs pipeline
  // (parsers / extensions / components / layout / theme) is configured via
  // [PageConfig.all]; the landing route is injected through [routerBuilder].
  runApp(
    ContentApp.custom(
      // Load markdown from `content` so files under `content/docs/*.md` map to
      // `/docs/*` (matching the sidebar links). `content/_data` is skipped — the
      // loader treats any path segment starting with `_` as private. `/` stays
      // owned by the landing page (no markdown sits in the content root).
      loaders: [
        FilesystemLoader('content'),
      ],
      configResolver: PageConfig.all(
        // Enables mustache templating inside the markdown files.
        templateEngine: MustacheTemplateEngine(),
        parsers: [
          MarkdownParser(),
        ],
        extensions: [
          // Adds heading anchors to each heading.
          HeadingAnchorsExtension(),
          // Generates a table of contents for each page.
          TableOfContentsExtension(),
        ],
        components: [
          // The <Info> block and other callouts.
          Callout(),
          // Adds syntax highlighting to code blocks.
          CodeBlock(),
          // Adds a custom Jaspr component to be used as <Clicker/> in markdown.
          CustomComponent(
            pattern: 'Clicker',
            builder: (_, _, _) => Clicker(),
          ),
          // Adds zooming and caption support to images.
          Image(zoom: true),
        ],
        layouts: [
          // Out-of-the-box layout for documentation sites.
          DocsLayout(
            header: Header(
              title: 'flutter_gemma',
              logo: '/images/logo.svg',
              items: [
                // Enables switching between light and dark mode.
                ThemeToggle(),
                // Shows github stats.
                GitHubButton(repo: 'DenisovAV/flutter_gemma'),
              ],
            ),
            sidebar: Sidebar(
              groups: [
                SidebarGroup(
                  links: [
                    SidebarLink(text: 'Overview', href: '/'),
                  ],
                ),
                SidebarGroup(
                  title: 'Guide',
                  links: [
                    SidebarLink(text: 'Getting Started', href: '/docs/getting-started'),
                    SidebarLink(text: 'Installation', href: '/docs/installation'),
                    SidebarLink(text: 'Models', href: '/docs/models'),
                  ],
                ),
                SidebarGroup(
                  title: 'Features',
                  links: [
                    SidebarLink(text: 'Multimodal', href: '/docs/multimodal'),
                    SidebarLink(text: 'Function Calling', href: '/docs/function-calling'),
                    SidebarLink(text: 'Thinking Mode', href: '/docs/thinking-mode'),
                    SidebarLink(text: 'Agent Skills', href: '/docs/agent'),
                    SidebarLink(text: 'Embeddings & RAG', href: '/docs/embeddings-and-rag'),
                  ],
                ),
                SidebarGroup(
                  title: 'Integrations',
                  links: [
                    SidebarLink(text: 'Genkit', href: '/docs/genkit'),
                  ],
                ),
                SidebarGroup(
                  title: 'Reference',
                  links: [
                    SidebarLink(text: 'Packages', href: '/docs/packages'),
                    SidebarLink(text: 'Desktop Support', href: '/docs/desktop'),
                    SidebarLink(text: 'Migration (0.x → 1.0)', href: '/docs/migration'),
                    SidebarLink(text: 'Troubleshooting', href: '/docs/troubleshooting'),
                  ],
                ),
              ],
            ),
          ),
        ],
        // Dark docs by default (navy canvas + light text), matching the
        // landing. jaspr_content applies the *light* color values at `:root`
        // unconditionally and *dark* only under `[data-theme="dark"]`, so to be
        // dark-by-default we set the navy/light palette as the LIGHT values.
        theme: ContentTheme(
          primary: Brand.blueLight,
          background: Brand.navy,
          text: Brand.white70,
          colors: [
            ContentColors.headings.apply(Brand.white),
            ContentColors.links.apply(Brand.blueLight),
            ContentColors.bold.apply(Brand.white),
            ContentColors.lead.apply(Brand.white70),
            ContentColors.code.apply(Brand.white),
            ContentColors.quotes.apply(Brand.white70),
            ContentColors.quoteBorders.apply(Brand.blue),
            ContentColors.counters.apply(Brand.white50),
            ContentColors.bullets.apply(Brand.blueLight),
            ContentColors.captions.apply(Brand.white50),
            ContentColors.hr.apply(const Color('rgba(255,255,255,0.12)')),
            ContentColors.thBorders.apply(const Color('rgba(255,255,255,0.18)')),
            ContentColors.tdBorders.apply(const Color('rgba(255,255,255,0.10)')),
            ContentColors.kbd.apply(Brand.white),
            ContentColors.preCode.apply(Brand.white70),
            ContentColors.preBg.apply(Brand.navyDeep),
          ],
          font: Brand.fontSans,
          codeFont: Brand.fontMono,
        ),
      ),
      // Inject the hand-built landing page at `/`, then spread the docs routes
      // generated from content/docs (served under their own paths).
      routerBuilder: (routes) => Router(
        routes: [
          Route(
            path: '/',
            // Full Document wrapper supplies <meta charset="utf-8"> (default),
            // title and description for the landing route. Without it, non-ASCII
            // glyphs (emoji, em-dashes) render as mojibake. `head:` adds the
            // Open Graph / Twitter Card / canonical tags (see seo.dart).
            builder: (context, state) => Document(
              title: 'flutter_gemma — On-device LLMs for Flutter',
              lang: 'en',
              meta: const {'description': _landingDescription},
              head: seoHead(
                title: 'flutter_gemma — On-device LLMs for Flutter',
                description: _landingDescription,
                path: '/',
              ),
              body: const LandingPage(),
            ),
          ),
          for (final group in routes) ...group,
        ],
      ),
    ),
  );
}
