#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for SentencePiece C++ library
@interface SentencePieceWrapper : NSObject

/// Load model from file path
/// @param path Path to sentencepiece.model file
/// @param error Error pointer
/// @return YES if successful
- (BOOL)loadModel:(NSString *)path error:(NSError **)error;

/// Encode text to token IDs
/// @param text Input text
/// @return Array of token IDs
- (NSArray<NSNumber *> *)encode:(NSString *)text;

/// Decode token IDs to text
/// @param ids Array of token IDs
/// @return Decoded text
- (NSString *)decode:(NSArray<NSNumber *> *)ids;

/// Get unknown token ID
- (NSInteger)unkId;

/// Get BOS token ID
- (NSInteger)bosId;

/// Get EOS token ID
- (NSInteger)eosId;

/// Convert piece string to ID
- (NSInteger)pieceToId:(NSString *)piece;

/// Convert ID to piece string
- (NSString *)idToPiece:(NSInteger)tokenId;

@end

NS_ASSUME_NONNULL_END
