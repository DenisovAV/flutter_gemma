package dev.flutterberlin.litertlm

import com.google.ai.edge.litertlm.*
import kotlin.reflect.full.memberProperties

fun main() {
    println("=== ConversationConfig ===")
    ConversationConfig::class.memberProperties.forEach { prop ->
        println("  ${prop.name}: ${prop.returnType}")
    }
    
    println("\n=== EngineConfig ===")
    EngineConfig::class.memberProperties.forEach { prop ->
        println("  ${prop.name}: ${prop.returnType}")
    }
    
    println("\n=== Conversation methods ===")
    Conversation::class.java.methods.forEach { method ->
        if (method.name.startsWith("send")) {
            println("  ${method.name}(${method.parameterTypes.map { it.simpleName }.joinToString(", ")}): ${method.returnType.simpleName}")
        }
    }
}
