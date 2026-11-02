//
//  XSalsa20Poly1305.swift
//  Tweetintosh
//
//  Pure Swift implementation of XSalsa20-Poly1305 authenticated symmetric encryption,
//  providing byte-for-byte compatibility with Libsodium's crypto_secretbox_easy / crypto_secretbox_open_easy.
//  Used by modern X Chat (End-to-End Encrypted Direct Messages) to secure message payloads.
//

import Foundation

infix operator <<< : BitwiseShiftPrecedence

fileprivate extension UInt32 {
    @inline(__always)
    static func <<< (lhs: UInt32, rhs: Int) -> UInt32 {
        return (lhs << rhs) | (lhs >> (32 - rhs))
    }
}

public struct XSalsa20Poly1305 {
    
    // MARK: - HSalsa20
    
    static func hsalsa20(key: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let sigma: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
        var x = [UInt32](repeating: 0, count: 16)
        var k = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            k[i] = UInt32(key[i*4]) | (UInt32(key[i*4+1]) << 8) | (UInt32(key[i*4+2]) << 16) | (UInt32(key[i*4+3]) << 24)
        }
        var n = [UInt32](repeating: 0, count: 4)
        for i in 0..<4 {
            n[i] = UInt32(nonce[i*4]) | (UInt32(nonce[i*4+1]) << 8) | (UInt32(nonce[i*4+2]) << 16) | (UInt32(nonce[i*4+3]) << 24)
        }
        
        x[0] = sigma[0]
        x[1] = k[0]; x[2] = k[1]; x[3] = k[2]; x[4] = k[3]
        x[5] = sigma[1]
        x[6] = n[0]; x[7] = n[1]; x[8] = n[2]; x[9] = n[3]
        x[10] = sigma[2]
        x[11] = k[4]; x[12] = k[5]; x[13] = k[6]; x[14] = k[7]
        x[15] = sigma[3]
        
        for _ in 0..<10 {
            // column round
            x[4] ^= (x[0] &+ x[12]) <<< 7; x[8] ^= (x[4] &+ x[0]) <<< 9
            x[12] ^= (x[8] &+ x[4]) <<< 13; x[0] ^= (x[12] &+ x[8]) <<< 18
            
            x[9] ^= (x[5] &+ x[1]) <<< 7; x[13] ^= (x[9] &+ x[5]) <<< 9
            x[1] ^= (x[13] &+ x[9]) <<< 13; x[5] ^= (x[1] &+ x[13]) <<< 18
            
            x[14] ^= (x[10] &+ x[6]) <<< 7; x[2] ^= (x[14] &+ x[10]) <<< 9
            x[6] ^= (x[2] &+ x[14]) <<< 13; x[10] ^= (x[6] &+ x[2]) <<< 18
            
            x[3] ^= (x[15] &+ x[11]) <<< 7; x[7] ^= (x[3] &+ x[15]) <<< 9
            x[11] ^= (x[7] &+ x[3]) <<< 13; x[15] ^= (x[11] &+ x[7]) <<< 18
            
            // row round
            x[1] ^= (x[0] &+ x[3]) <<< 7; x[2] ^= (x[1] &+ x[0]) <<< 9
            x[3] ^= (x[2] &+ x[1]) <<< 13; x[0] ^= (x[3] &+ x[2]) <<< 18
            
            x[6] ^= (x[5] &+ x[4]) <<< 7; x[7] ^= (x[6] &+ x[5]) <<< 9
            x[4] ^= (x[7] &+ x[6]) <<< 13; x[5] ^= (x[4] &+ x[7]) <<< 18
            
            x[11] ^= (x[10] &+ x[9]) <<< 7; x[8] ^= (x[11] &+ x[10]) <<< 9
            x[9] ^= (x[8] &+ x[11]) <<< 13; x[10] ^= (x[9] &+ x[8]) <<< 18
            
            x[12] ^= (x[15] &+ x[14]) <<< 7; x[13] ^= (x[12] &+ x[15]) <<< 9
            x[14] ^= (x[13] &+ x[12]) <<< 13; x[15] ^= (x[14] &+ x[13]) <<< 18
        }
        
        let outIndices = [0, 5, 10, 15, 6, 7, 8, 9]
        var out = [UInt8]()
        out.reserveCapacity(32)
        for idx in outIndices {
            let v = x[idx]
            out.append(UInt8(v & 0xff))
            out.append(UInt8((v >> 8) & 0xff))
            out.append(UInt8((v >> 16) & 0xff))
            out.append(UInt8((v >> 24) & 0xff))
        }
        return out
    }
    
    // MARK: - Salsa20 Keystream
    
    static func salsa20Keystream(key: [UInt8], nonce: [UInt8], length: Int) -> [UInt8] {
        let sigma: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
        var k = [UInt32](repeating: 0, count: 8)
        for i in 0..<8 {
            k[i] = UInt32(key[i*4]) | (UInt32(key[i*4+1]) << 8) | (UInt32(key[i*4+2]) << 16) | (UInt32(key[i*4+3]) << 24)
        }
        var n = [UInt32](repeating: 0, count: 2)
        for i in 0..<2 {
            n[i] = UInt32(nonce[i*4]) | (UInt32(nonce[i*4+1]) << 8) | (UInt32(nonce[i*4+2]) << 16) | (UInt32(nonce[i*4+3]) << 24)
        }
        
        var stream = [UInt8]()
        stream.reserveCapacity(length)
        var counter: UInt64 = 0
        
        while stream.count < length {
            var orig = [UInt32](repeating: 0, count: 16)
            orig[0] = sigma[0]
            orig[1] = k[0]; orig[2] = k[1]; orig[3] = k[2]; orig[4] = k[3]
            orig[5] = sigma[1]
            orig[6] = n[0]; orig[7] = n[1]
            orig[8] = UInt32(counter & 0xffffffff)
            orig[9] = UInt32((counter >> 32) & 0xffffffff)
            orig[10] = sigma[2]
            orig[11] = k[4]; orig[12] = k[5]; orig[13] = k[6]; orig[14] = k[7]
            orig[15] = sigma[3]
            
            var x = orig
            for _ in 0..<10 {
                // column round
                x[4] ^= (x[0] &+ x[12]) <<< 7; x[8] ^= (x[4] &+ x[0]) <<< 9
                x[12] ^= (x[8] &+ x[4]) <<< 13; x[0] ^= (x[12] &+ x[8]) <<< 18
                
                x[9] ^= (x[5] &+ x[1]) <<< 7; x[13] ^= (x[9] &+ x[5]) <<< 9
                x[1] ^= (x[13] &+ x[9]) <<< 13; x[5] ^= (x[1] &+ x[13]) <<< 18
                
                x[14] ^= (x[10] &+ x[6]) <<< 7; x[2] ^= (x[14] &+ x[10]) <<< 9
                x[6] ^= (x[2] &+ x[14]) <<< 13; x[10] ^= (x[6] &+ x[2]) <<< 18
                
                x[3] ^= (x[15] &+ x[11]) <<< 7; x[7] ^= (x[3] &+ x[15]) <<< 9
                x[11] ^= (x[7] &+ x[3]) <<< 13; x[15] ^= (x[11] &+ x[7]) <<< 18
                
                // row round
                x[1] ^= (x[0] &+ x[3]) <<< 7; x[2] ^= (x[1] &+ x[0]) <<< 9
                x[3] ^= (x[2] &+ x[1]) <<< 13; x[0] ^= (x[3] &+ x[2]) <<< 18
                
                x[6] ^= (x[5] &+ x[4]) <<< 7; x[7] ^= (x[6] &+ x[5]) <<< 9
                x[4] ^= (x[7] &+ x[6]) <<< 13; x[5] ^= (x[4] &+ x[7]) <<< 18
                
                x[11] ^= (x[10] &+ x[9]) <<< 7; x[8] ^= (x[11] &+ x[10]) <<< 9
                x[9] ^= (x[8] &+ x[11]) <<< 13; x[10] ^= (x[9] &+ x[8]) <<< 18
                
                x[12] ^= (x[15] &+ x[14]) <<< 7; x[13] ^= (x[12] &+ x[15]) <<< 9
                x[14] ^= (x[13] &+ x[12]) <<< 13; x[15] ^= (x[14] &+ x[13]) <<< 18
            }
            
            for i in 0..<16 {
                let v = x[i] &+ orig[i]
                if stream.count < length { stream.append(UInt8(v & 0xff)) }
                if stream.count < length { stream.append(UInt8((v >> 8) & 0xff)) }
                if stream.count < length { stream.append(UInt8((v >> 16) & 0xff)) }
                if stream.count < length { stream.append(UInt8((v >> 24) & 0xff)) }
            }
            counter += 1
        }
        return stream
    }
    
    // MARK: - Poly1305 MAC (TweetNaCl Compatible)
    
    private struct TweetNaClPoly1305Engine {
        var buffer = [UInt8](repeating: 0, count: 16)
        var r = [UInt32](repeating: 0, count: 10)
        var h = [UInt32](repeating: 0, count: 10)
        var pad = [UInt32](repeating: 0, count: 8)
        var leftover = 0
        var fin = 0
        
        init(key: [UInt8]) {
            let t0 = UInt32(key[0]) | (UInt32(key[1]) << 8)
            r[0] = t0 & 0x1fff
            let t1 = UInt32(key[2]) | (UInt32(key[3]) << 8)
            r[1] = ((t0 >> 13) | (t1 << 3)) & 0x1fff
            let t2 = UInt32(key[4]) | (UInt32(key[5]) << 8)
            r[2] = ((t1 >> 10) | (t2 << 6)) & 0x1f03
            let t3 = UInt32(key[6]) | (UInt32(key[7]) << 8)
            r[3] = ((t2 >> 7) | (t3 << 9)) & 0x1fff
            let t4 = UInt32(key[8]) | (UInt32(key[9]) << 8)
            r[4] = ((t3 >> 4) | (t4 << 12)) & 0x00ff
            r[5] = (t4 >> 1) & 0x1ffe
            let t5 = UInt32(key[10]) | (UInt32(key[11]) << 8)
            r[6] = ((t4 >> 14) | (t5 << 2)) & 0x1fff
            let t6 = UInt32(key[12]) | (UInt32(key[13]) << 8)
            r[7] = ((t5 >> 11) | (t6 << 5)) & 0x1f81
            let t7 = UInt32(key[14]) | (UInt32(key[15]) << 8)
            r[8] = ((t6 >> 8) | (t7 << 8)) & 0x1fff
            r[9] = (t7 >> 5) & 0x007f
            
            for i in 0..<8 {
                pad[i] = UInt32(key[16 + i*2]) | (UInt32(key[17 + i*2]) << 8)
            }
        }
        
        mutating func blocks(m: [UInt8], mpos: Int, bytes: Int) {
            let hibit: UInt32 = fin != 0 ? 0 : (1 << 11)
            var pos = mpos
            var rem = bytes
            
            var h0 = h[0], h1 = h[1], h2 = h[2], h3 = h[3], h4 = h[4]
            var h5 = h[5], h6 = h[6], h7 = h[7], h8 = h[8], h9 = h[9]
            
            let r0 = r[0], r1 = r[1], r2 = r[2], r3 = r[3], r4 = r[4]
            let r5 = r[5], r6 = r[6], r7 = r[7], r8 = r[8], r9 = r[9]
            
            while rem >= 16 {
                let t0 = UInt32(m[pos + 0]) | (UInt32(m[pos + 1]) << 8); h0 += t0 & 0x1fff
                let t1 = UInt32(m[pos + 2]) | (UInt32(m[pos + 3]) << 8); h1 += ((t0 >> 13) | (t1 << 3)) & 0x1fff
                let t2 = UInt32(m[pos + 4]) | (UInt32(m[pos + 5]) << 8); h2 += ((t1 >> 10) | (t2 << 6)) & 0x1fff
                let t3 = UInt32(m[pos + 6]) | (UInt32(m[pos + 7]) << 8); h3 += ((t2 >> 7) | (t3 << 9)) & 0x1fff
                let t4 = UInt32(m[pos + 8]) | (UInt32(m[pos + 9]) << 8); h4 += ((t3 >> 4) | (t4 << 12)) & 0x1fff
                h5 += (t4 >> 1) & 0x1fff
                let t5 = UInt32(m[pos + 10]) | (UInt32(m[pos + 11]) << 8); h6 += ((t4 >> 14) | (t5 << 2)) & 0x1fff
                let t6 = UInt32(m[pos + 12]) | (UInt32(m[pos + 13]) << 8); h7 += ((t5 >> 11) | (t6 << 5)) & 0x1fff
                let t7 = UInt32(m[pos + 14]) | (UInt32(m[pos + 15]) << 8); h8 += ((t6 >> 8) | (t7 << 8)) & 0x1fff
                h9 += (t7 >> 5) | hibit
                
                var c: UInt32 = 0
                
                var d0 = c
                d0 += h0 * r0
                d0 += h1 * (5 * r9)
                d0 += h2 * (5 * r8)
                d0 += h3 * (5 * r7)
                d0 += h4 * (5 * r6)
                c = d0 >> 13; d0 &= 0x1fff
                d0 += h5 * (5 * r5)
                d0 += h6 * (5 * r4)
                d0 += h7 * (5 * r3)
                d0 += h8 * (5 * r2)
                d0 += h9 * (5 * r1)
                c += d0 >> 13; d0 &= 0x1fff
                
                var d1 = c
                d1 += h0 * r1
                d1 += h1 * r0
                d1 += h2 * (5 * r9)
                d1 += h3 * (5 * r8)
                d1 += h4 * (5 * r7)
                c = d1 >> 13; d1 &= 0x1fff
                d1 += h5 * (5 * r6)
                d1 += h6 * (5 * r5)
                d1 += h7 * (5 * r4)
                d1 += h8 * (5 * r3)
                d1 += h9 * (5 * r2)
                c += d1 >> 13; d1 &= 0x1fff
                
                var d2 = c
                d2 += h0 * r2
                d2 += h1 * r1
                d2 += h2 * r0
                d2 += h3 * (5 * r9)
                d2 += h4 * (5 * r8)
                c = d2 >> 13; d2 &= 0x1fff
                d2 += h5 * (5 * r7)
                d2 += h6 * (5 * r6)
                d2 += h7 * (5 * r5)
                d2 += h8 * (5 * r4)
                d2 += h9 * (5 * r3)
                c += d2 >> 13; d2 &= 0x1fff
                
                var d3 = c
                d3 += h0 * r3
                d3 += h1 * r2
                d3 += h2 * r1
                d3 += h3 * r0
                d3 += h4 * (5 * r9)
                c = d3 >> 13; d3 &= 0x1fff
                d3 += h5 * (5 * r8)
                d3 += h6 * (5 * r7)
                d3 += h7 * (5 * r6)
                d3 += h8 * (5 * r5)
                d3 += h9 * (5 * r4)
                c += d3 >> 13; d3 &= 0x1fff
                
                var d4 = c
                d4 += h0 * r4
                d4 += h1 * r3
                d4 += h2 * r2
                d4 += h3 * r1
                d4 += h4 * r0
                c = d4 >> 13; d4 &= 0x1fff
                d4 += h5 * (5 * r9)
                d4 += h6 * (5 * r8)
                d4 += h7 * (5 * r7)
                d4 += h8 * (5 * r6)
                d4 += h9 * (5 * r5)
                c += d4 >> 13; d4 &= 0x1fff
                
                var d5 = c
                d5 += h0 * r5
                d5 += h1 * r4
                d5 += h2 * r3
                d5 += h3 * r2
                d5 += h4 * r1
                c = d5 >> 13; d5 &= 0x1fff
                d5 += h5 * r0
                d5 += h6 * (5 * r9)
                d5 += h7 * (5 * r8)
                d5 += h8 * (5 * r7)
                d5 += h9 * (5 * r6)
                c += d5 >> 13; d5 &= 0x1fff
                
                var d6 = c
                d6 += h0 * r6
                d6 += h1 * r5
                d6 += h2 * r4
                d6 += h3 * r3
                d6 += h4 * r2
                c = d6 >> 13; d6 &= 0x1fff
                d6 += h5 * r1
                d6 += h6 * r0
                d6 += h7 * (5 * r9)
                d6 += h8 * (5 * r8)
                d6 += h9 * (5 * r7)
                c += d6 >> 13; d6 &= 0x1fff
                
                var d7 = c
                d7 += h0 * r7
                d7 += h1 * r6
                d7 += h2 * r5
                d7 += h3 * r4
                d7 += h4 * r3
                c = d7 >> 13; d7 &= 0x1fff
                d7 += h5 * r2
                d7 += h6 * r1
                d7 += h7 * r0
                d7 += h8 * (5 * r9)
                d7 += h9 * (5 * r8)
                c += d7 >> 13; d7 &= 0x1fff
                
                var d8 = c
                d8 += h0 * r8
                d8 += h1 * r7
                d8 += h2 * r6
                d8 += h3 * r5
                d8 += h4 * r4
                c = d8 >> 13; d8 &= 0x1fff
                d8 += h5 * r3
                d8 += h6 * r2
                d8 += h7 * r1
                d8 += h8 * r0
                d8 += h9 * (5 * r9)
                c += d8 >> 13; d8 &= 0x1fff
                
                var d9 = c
                d9 += h0 * r9
                d9 += h1 * r8
                d9 += h2 * r7
                d9 += h3 * r6
                d9 += h4 * r5
                c = d9 >> 13; d9 &= 0x1fff
                d9 += h5 * r4
                d9 += h6 * r3
                d9 += h7 * r2
                d9 += h8 * r1
                d9 += h9 * r0
                c += d9 >> 13; d9 &= 0x1fff
                
                c = (c << 2) + c
                c += d0
                d0 = c & 0x1fff
                c >>= 13
                d1 += c
                
                h0 = d0
                h1 = d1
                h2 = d2
                h3 = d3
                h4 = d4
                h5 = d5
                h6 = d6
                h7 = d7
                h8 = d8
                h9 = d9
                
                pos += 16
                rem -= 16
            }
            
            h[0] = h0; h[1] = h1; h[2] = h2; h[3] = h3; h[4] = h4
            h[5] = h5; h[6] = h6; h[7] = h7; h[8] = h8; h[9] = h9
        }
        
        mutating func update(message: [UInt8]) {
            var mpos = 0
            var bytes = message.count
            
            if leftover > 0 {
                var want = 16 - leftover
                if want > bytes { want = bytes }
                for i in 0..<want { buffer[leftover + i] = message[mpos + i] }
                bytes -= want
                mpos += want
                leftover += want
                if leftover < 16 { return }
                blocks(m: buffer, mpos: 0, bytes: 16)
                leftover = 0
            }
            
            if bytes >= 16 {
                let want = bytes & ~15
                blocks(m: message, mpos: mpos, bytes: want)
                mpos += want
                bytes -= want
            }
            
            if bytes > 0 {
                for i in 0..<bytes { buffer[leftover + i] = message[mpos + i] }
                leftover += bytes
            }
        }
        
        mutating func finish() -> [UInt8] {
            var g = [UInt32](repeating: 0, count: 10)
            
            if leftover > 0 {
                var i = leftover
                buffer[i] = 1
                i += 1
                for k in i..<16 { buffer[k] = 0 }
                fin = 1
                blocks(m: buffer, mpos: 0, bytes: 16)
            }
            
            var c = h[1] >> 13
            h[1] &= 0x1fff
            for i in 2..<10 {
                h[i] += c
                c = h[i] >> 13
                h[i] &= 0x1fff
            }
            h[0] += c * 5
            c = h[0] >> 13
            h[0] &= 0x1fff
            h[1] += c
            c = h[1] >> 13
            h[1] &= 0x1fff
            h[2] += c
            
            g[0] = h[0] + 5
            c = g[0] >> 13
            g[0] &= 0x1fff
            for i in 1..<10 {
                g[i] = h[i] + c
                c = g[i] >> 13
                g[i] &= 0x1fff
            }
            g[9] &-= (1 << 13)
            
            let mask = (c ^ 1) &- 1
            for i in 0..<10 { g[i] &= mask }
            let nmask = ~mask
            for i in 0..<10 { h[i] = (h[i] & nmask) | g[i] }
            
            h[0] = ((h[0]) | (h[1] << 13)) & 0xffff
            h[1] = ((h[1] >> 3) | (h[2] << 10)) & 0xffff
            h[2] = ((h[2] >> 6) | (h[3] << 7)) & 0xffff
            h[3] = ((h[3] >> 9) | (h[4] << 4)) & 0xffff
            h[4] = ((h[4] >> 12) | (h[5] << 1) | (h[6] << 14)) & 0xffff
            h[5] = ((h[6] >> 2) | (h[7] << 11)) & 0xffff
            h[6] = ((h[7] >> 5) | (h[8] << 8)) & 0xffff
            h[7] = ((h[8] >> 8) | (h[9] << 5)) & 0xffff
            
            var f = h[0] + pad[0]
            h[0] = f & 0xffff
            for i in 1..<8 {
                f = (h[i] + pad[i]) + (f >> 16)
                h[i] = f & 0xffff
            }
            
            var mac = [UInt8](repeating: 0, count: 16)
            mac[0] = UInt8(h[0] & 0xff); mac[1] = UInt8((h[0] >> 8) & 0xff)
            mac[2] = UInt8(h[1] & 0xff); mac[3] = UInt8((h[1] >> 8) & 0xff)
            mac[4] = UInt8(h[2] & 0xff); mac[5] = UInt8((h[2] >> 8) & 0xff)
            mac[6] = UInt8(h[3] & 0xff); mac[7] = UInt8((h[3] >> 8) & 0xff)
            mac[8] = UInt8(h[4] & 0xff); mac[9] = UInt8((h[4] >> 8) & 0xff)
            mac[10] = UInt8(h[5] & 0xff); mac[11] = UInt8((h[5] >> 8) & 0xff)
            mac[12] = UInt8(h[6] & 0xff); mac[13] = UInt8((h[6] >> 8) & 0xff)
            mac[14] = UInt8(h[7] & 0xff); mac[15] = UInt8((h[7] >> 8) & 0xff)
            return mac
        }
    }
    
    public static func poly1305(key: [UInt8], message: [UInt8]) -> [UInt8] {
        var engine = TweetNaClPoly1305Engine(key: key)
        engine.update(message: message)
        return engine.finish()
    }
    
    // MARK: - Open Easy (Decrypt XSalsa20-Poly1305 payload)
    
    /// Decrypts payload formatted as [16-byte MAC || ciphertext] using 24-byte nonce and 32-byte key.
    /// Perfectly mirrors Libsodium's crypto_secretbox_open_easy.
    public static func open(box: Data, nonce: Data, key: Data) -> Data? {
        guard box.count >= 16, nonce.count == 24, key.count == 32 else { return nil }
        
        let keyBytes = Array(key)
        let nonceBytes = Array(nonce)
        let boxBytes = Array(box)
        
        let subKey = hsalsa20(key: keyBytes, nonce: Array(nonceBytes[0..<16]))
        let stream = salsa20Keystream(key: subKey, nonce: Array(nonceBytes[16..<24]), length: boxBytes.count + 16)
        
        let polyKey = Array(stream[0..<32])
        let ciphertext = Array(boxBytes[16...])
        let expectedTag = Array(boxBytes[0..<16])
        
        let computedTag = poly1305(key: polyKey, message: ciphertext)
        
        // Constant-time compare tag
        var diff: UInt8 = 0
        for i in 0..<16 {
            diff |= computedTag[i] ^ expectedTag[i]
        }
        guard diff == 0 else {
            return nil
        }
        
        var plaintext = [UInt8]()
        plaintext.reserveCapacity(ciphertext.count)
        for i in 0..<ciphertext.count {
            plaintext.append(ciphertext[i] ^ stream[32 + i])
        }
        return Data(plaintext)
    }
    
    // MARK: - Seal Easy (Encrypt XSalsa20-Poly1305 payload)
    
    /// Encrypts message formatted as [16-byte MAC || ciphertext] using 24-byte nonce and 32-byte key.
    /// Perfectly mirrors Libsodium's crypto_secretbox_easy.
    public static func seal(message: Data, nonce: Data, key: Data) -> Data? {
        guard nonce.count == 24, key.count == 32 else { return nil }
        let keyBytes = Array(key)
        let nonceBytes = Array(nonce)
        let msgBytes = Array(message)
        
        let subKey = hsalsa20(key: keyBytes, nonce: Array(nonceBytes[0..<16]))
        let stream = salsa20Keystream(key: subKey, nonce: Array(nonceBytes[16..<24]), length: msgBytes.count + 32)
        let polyKey = Array(stream[0..<32])
        
        var ciphertext = [UInt8]()
        ciphertext.reserveCapacity(msgBytes.count)
        for i in 0..<msgBytes.count {
            ciphertext.append(msgBytes[i] ^ stream[32 + i])
        }
        let tag = poly1305(key: polyKey, message: ciphertext)
        return Data(tag + ciphertext)
    }
}
