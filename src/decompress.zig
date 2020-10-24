const std = @import("std");
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;

const CanonicalCode = struct {
    code_bits_to_symbol: AutoHashMap(u16, u9),

    pub fn init(allocator: *Allocator, codelengths: []const u8) !@This() {
        var code_bits_to_symbol = AutoHashMap(u16, u9).init(allocator);
        errdefer code_bits_to_symbol.deinit();

        var max_codelength = codelengths[0];
        for (codelengths[1..]) |codelength| {
            if (codelength > max_codelength) {
                max_codelength = codelength;
            }
        }

        var nextcode: u16 = 0;
        var codelength: u8 = 1;
        while (codelength <= max_codelength) : (codelength += 1) {
            nextcode <<= 1;
            const startbit = @as(u16, 1) << @intCast(u4, codelength);
            for (codelengths) |codelen, symbol| {
                if (codelen != codelength) {
                    continue;
                }
                if (nextcode >= startbit) {
                    return error.OverFullHuffmanCoding;
                }
                try code_bits_to_symbol.put(startbit | nextcode, @intCast(u9, symbol));
                nextcode += 1;
            }
        }
        if (nextcode != (@as(u16, 1) << @intCast(u4, max_codelength))) {
            return error.UnderFullHuffmanCoding;
        }
        return @This(){
            .code_bits_to_symbol = code_bits_to_symbol,
        };
    }

    pub fn deinit(this: *@This()) void {
        this.code_bits_to_symbol.deinit();
    }

    pub fn decode_next_symbol(this: @This(), bit_reader: anytype) !?u9 {
        var codebits: u9 = 1;
        while (true) {
            var out_bits: usize = undefined;
            const next_bit = try bit_reader.readBits(u1, 1, &out_bits);
            if (out_bits == 0) return null;
            std.debug.assert(out_bits == 1);
            
            codebits <<= 1;
            codebits |= next_bit;

            if (this.code_bits_to_symbol.get(codebits)) |symbol| {
                return symbol;
            }
        }
    }
};

const FIXED_HUFFMAN_CODELENGTHS: [288]u8 = [_]u8{8} ** 144 ++ [_]u8{9} ** 112 ++ [_]u8{7} ** 24 ++ [_]u8{8} ** 8;

test "decode using fixed huffman codelengths" {
    var fixed_code = try CanonicalCode.init(std.testing.allocator, &FIXED_HUFFMAN_CODELENGTHS);
    defer fixed_code.deinit();

    const mem_be = [_]u8{0b01111000};
    var fixed_buffer_stream = std.io.fixedBufferStream(&mem_be);
    var bit_reader = std.io.bitReader(.Big, fixed_buffer_stream.reader());

    const symbol = (try fixed_code.decode_next_symbol(&bit_reader)).?;
    std.log.warn("\n{x}\n{b}\n{c}\n", .{symbol, symbol, @intCast(u8, symbol)});
}
