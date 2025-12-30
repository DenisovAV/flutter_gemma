package dev.flutterberlin.litertlm

import io.grpc.ServerBuilder
import java.util.concurrent.TimeUnit
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("LiteRtLmServer")

fun main(args: Array<String>) {
    val port = args.getOrElse(0) { "50051" }.toInt()

    val service = LiteRtLmServiceImpl()

    val server = ServerBuilder
        .forPort(port)
        .addService(service)
        .maxInboundMessageSize(100 * 1024 * 1024) // 100MB for images
        .build()

    server.start()
    logger.info("LiteRT-LM Server started on port $port")
    println("LiteRT-LM Server started on port $port")

    Runtime.getRuntime().addShutdownHook(Thread {
        logger.info("Shutting down LiteRT-LM Server...")
        service.shutdown()
        server.shutdown()
        server.awaitTermination(30, TimeUnit.SECONDS)
        logger.info("LiteRT-LM Server stopped")
    })

    server.awaitTermination()
}
