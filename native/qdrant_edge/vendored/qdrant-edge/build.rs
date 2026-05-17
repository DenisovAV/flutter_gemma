mod build_common;
mod build_quantization;
mod build_segment;
fn main() {
    build_common::main();
    build_quantization::main();
    build_segment::main();
}
