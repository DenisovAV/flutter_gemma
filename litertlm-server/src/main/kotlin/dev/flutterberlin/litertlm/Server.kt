package dev.flutterberlin.litertlm

import io.grpc.ServerBuilder
import java.util.concurrent.TimeUnit
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("LiteRtLmServer")

// Immediately flush stdout after each message for real-time output
// Windows buffers stdout which causes "hanging" appearance
private fun log(message: String) {
    println(message)
    System.out.flush()
    logger.info(message)
}

fun main(args: Array<String>) {
    log("=== LiteRT-LM Server ===")
    log("Starting up...")
    log("Arguments: ${args.joinToString()}")

    val port = args.getOrElse(0) { "50051" }.toInt()
    log("Port: $port")

    log("Java version: ${System.getProperty("java.version")}")
    log("Java home: ${System.getProperty("java.home")}")
    log("Library path: ${System.getProperty("java.library.path")}")

    log("Creating gRPC service...")
    val service = LiteRtLmServiceImpl()
    log("Service created")

    log("Building gRPC server...")
    val server = ServerBuilder
        .forPort(port)
        .addService(service)
        .maxInboundMessageSize(100 * 1024 * 1024) // 100MB for images
        .build()
    log("Server built")

    log("Starting gRPC server...")
    server.start()
    log("LiteRT-LM Server started on port $port")

    Runtime.getRuntime().addShutdownHook(Thread {
        log("Shutting down LiteRT-LM Server...")
        service.shutdown()
        server.shutdown()
        server.awaitTermination(30, TimeUnit.SECONDS)
        log("LiteRT-LM Server stopped")
    })

    log("Awaiting termination...")
    server.awaitTermination()
}
