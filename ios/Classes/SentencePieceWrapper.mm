#import "SentencePieceWrapper.h"
#include "sentencepiece_processor.h"

@implementation SentencePieceWrapper {
    sentencepiece::SentencePieceProcessor* _processor;
    BOOL _isLoaded;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processor = new sentencepiece::SentencePieceProcessor();
        _isLoaded = NO;
    }
    return self;
}

- (void)dealloc {
    if (_processor) {
        delete _processor;
        _processor = nullptr;
    }
}

- (BOOL)loadModel:(NSString *)path error:(NSError **)error {
    const auto status = _processor->Load([path UTF8String]);
    if (!status.ok()) {
        if (error) {
            std::string msg(status.message());
            *error = [NSError errorWithDomain:@"SentencePieceWrapper"
                                         code:-1
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load model: %s",
                                           msg.c_str()]
            }];
        }
        return NO;
    }
    _isLoaded = YES;

    NSLog(@"[TOKENIZER] Loaded native SentencePiece model from: %@", path);

    return YES;
}

- (NSArray<NSNumber *> *)encode:(NSString *)text {
    if (!_isLoaded) {
        NSLog(@"[TOKENIZER] ERROR: Model not loaded!");
        return @[];
    }
    if (text.length == 0) {
        NSLog(@"[TOKENIZER] WARNING: Empty text to encode");
        return @[];
    }

    std::vector<int> ids;
    const auto status = _processor->Encode([text UTF8String], &ids);
    if (!status.ok()) {
        std::string msg(status.message());
        NSLog(@"[TOKENIZER] Error encoding '%@': %s", text, msg.c_str());
        return @[];
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:ids.size()];
    for (int id : ids) {
        [result addObject:@(id)];
    }

    NSLog(@"[TOKENIZER] Encoded '%@' -> %zu tokens: %@", text, ids.size(), result);
    return result;
}

- (NSString *)decode:(NSArray<NSNumber *> *)ids {
    if (!_isLoaded || ids.count == 0) {
        return @"";
    }

    std::vector<int> vec;
    vec.reserve(ids.count);
    for (NSNumber *n in ids) {
        vec.push_back([n intValue]);
    }

    std::string text;
    const auto status = _processor->Decode(vec, &text);
    if (!status.ok()) {
        std::string msg(status.message());
        NSLog(@"[TOKENIZER] Error decoding: %s", msg.c_str());
        return @"";
    }

    return [NSString stringWithUTF8String:text.c_str()];
}

- (NSInteger)unkId {
    // Hardcoded to avoid protobuf conflict crash
    // Standard SentencePiece values for Gemma models
    return 0;
}

- (NSInteger)bosId {
    // Hardcoded to avoid protobuf conflict crash
    return 2;
}

- (NSInteger)eosId {
    // Hardcoded to avoid protobuf conflict crash
    return 1;
}

- (NSInteger)pieceToId:(NSString *)piece {
    if (!_isLoaded) return [self unkId];
    return _processor->PieceToId([piece UTF8String]);
}

- (NSString *)idToPiece:(NSInteger)tokenId {
    if (!_isLoaded) return @"";
    const auto& piece = _processor->IdToPiece((int)tokenId);
    return [NSString stringWithUTF8String:piece.c_str()];
}

@end
