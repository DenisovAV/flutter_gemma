import Foundation

protocol TokenizerProtocol {
    func encode(_ text: String) -> [Int]
    func decode(_ tokens: [Int]) -> String
    func getUnkTokenId() -> Int
    func getBosTokenId() -> Int
    func getEosTokenId() -> Int
}
