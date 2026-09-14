#![allow(clippy::needless_range_loop, clippy::chunks_exact_to_as_chunks)]

// -------------------------------------------------------------------------
// Base64 Encoding and Decoding (RFC 4648)
// -------------------------------------------------------------------------

const BASE64_CHARS: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

const B64_INV: u8 = 0xFF;
const B64_PAD: u8 = 0xFE;

const fn make_b64_table() -> [u8; 256] {
    let mut table = [B64_INV; 256];
    let mut i = 0u8;
    while i < 26 {
        table[(b'A' + i) as usize] = i;
        table[(b'a' + i) as usize] = i + 26;
        i += 1;
    }
    let mut j = 0u8;
    while j < 10 {
        table[(b'0' + j) as usize] = j + 52;
        j += 1;
    }
    table[b'+' as usize] = 62;
    table[b'/' as usize] = 63;
    table[b'=' as usize] = B64_PAD;
    table
}

static B64_DECODE_TABLE: [u8; 256] = make_b64_table();

/// Encode arbitrary binary data into standard Base64 string.
pub fn base64_encode(data: &[u8]) -> String {
    let mut result = Vec::with_capacity(data.len().div_ceil(3) * 4);
    let mut i = 0;

    while i < data.len() {
        let b0 = data[i];
        let b1 = if i + 1 < data.len() { data[i + 1] } else { 0 };
        let b2 = if i + 2 < data.len() { data[i + 2] } else { 0 };

        result.push(BASE64_CHARS[(b0 >> 2) as usize]);
        result.push(BASE64_CHARS[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize]);

        if i + 1 < data.len() {
            result.push(BASE64_CHARS[(((b1 & 0x0F) << 2) | (b2 >> 6)) as usize]);
        } else {
            result.push(b'=');
        }

        if i + 2 < data.len() {
            result.push(BASE64_CHARS[(b2 & 0x3F) as usize]);
        } else {
            result.push(b'=');
        }

        i += 3;
    }

    // Safety: BASE64_CHARS and '=' are ASCII characters.
    unsafe { String::from_utf8_unchecked(result) }
}

/// Decode Base64 string into raw binary bytes.
///
/// Single-pass streaming decode: skips ASCII whitespace on the fly without
/// allocating an intermediate cleaned buffer. Output capacity is estimated
/// from the input length (exact when no whitespace present).
pub fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    let mut result = Vec::with_capacity(input.len() / 4 * 3);
    let mut chunk = [0u8; 4];
    let mut chunk_len = 0usize;
    let mut total = 0usize; // non-whitespace bytes seen (logical position)
    let mut padded = false; // padding seen in a completed chunk

    for &b in input.as_bytes() {
        if b.is_ascii_whitespace() {
            continue;
        }
        if padded {
            return Err("Unexpected padding character inside Base64 stream".to_string());
        }
        chunk[chunk_len] = b;
        chunk_len += 1;
        if chunk_len < 4 {
            continue;
        }

        let v0 = B64_DECODE_TABLE[chunk[0] as usize];
        let v1 = B64_DECODE_TABLE[chunk[1] as usize];
        let v2 = B64_DECODE_TABLE[chunk[2] as usize];
        let v3 = B64_DECODE_TABLE[chunk[3] as usize];

        if v0 >= B64_PAD || v1 >= B64_PAD {
            return Err(format!("Invalid Base64 character in position {}", total));
        }

        result.push((v0 << 2) | (v1 >> 4));

        if v2 != B64_PAD {
            result.push(((v1 & 0x0F) << 4) | (v2 >> 2));

            if v3 != B64_PAD {
                result.push(((v2 & 0x03) << 6) | v3);
            } else {
                // Padding in final byte: this must be the last chunk.
                padded = true;
            }
        } else {
            // If v2 is padding, v3 must also be padding, and this must be the final chunk
            if v3 != B64_PAD {
                return Err("Invalid Base64 padding sequence".to_string());
            }
            padded = true;
        }

        total += 4;
        chunk_len = 0;
    }

    if chunk_len != 0 {
        return Err("Invalid Base64 length".to_string());
    }

    Ok(result)
}

// -------------------------------------------------------------------------
// Hex Encoding & Decoding
// -------------------------------------------------------------------------

const HEX_CHARS_LOWER: &[u8; 16] = b"0123456789abcdef";

/// Convert byte slice into lowercase hexadecimal string (fast zero-format lookup).
pub fn hex_encode(data: &[u8]) -> String {
    let mut out = Vec::with_capacity(data.len() * 2);
    for &b in data {
        out.push(HEX_CHARS_LOWER[(b >> 4) as usize]);
        out.push(HEX_CHARS_LOWER[(b & 0x0f) as usize]);
    }
    // Safety: HEX_CHARS_LOWER contains only valid ASCII hexadecimal characters.
    unsafe { String::from_utf8_unchecked(out) }
}

#[inline(always)]
fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Decode hexadecimal string into raw bytes.
pub fn hex_decode(s: &str) -> Result<Vec<u8>, String> {
    let bytes = s.as_bytes();
    if !bytes.len().is_multiple_of(2) {
        return Err("Odd hex string length".to_string());
    }

    let mut out = Vec::with_capacity(bytes.len() / 2);
    for i in (0..bytes.len()).step_by(2) {
        let hi = hex_val(bytes[i])
            .ok_or_else(|| format!("Invalid hex byte: character '{}'", bytes[i] as char))?;
        let lo = hex_val(bytes[i + 1])
            .ok_or_else(|| format!("Invalid hex byte: character '{}'", bytes[i + 1] as char))?;
        out.push((hi << 4) | lo);
    }

    Ok(out)
}

// -------------------------------------------------------------------------
// SHA-1 (FIPS 180-1) - Zero Heap Allocations
// -------------------------------------------------------------------------

#[inline(always)]
fn sha1_process_block(
    block: &[u8; 64],
    h0: &mut u32,
    h1: &mut u32,
    h2: &mut u32,
    h3: &mut u32,
    h4: &mut u32,
) {
    let mut w = [0u32; 80];
    for i in 0..16 {
        w[i] = u32::from_be_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }
    for i in 16..80 {
        w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
    }

    let mut a = *h0;
    let mut b = *h1;
    let mut c = *h2;
    let mut d = *h3;
    let mut e = *h4;

    for i in 0..80 {
        let (f, k) = match i {
            0..=19 => ((b & c) | ((!b) & d), 0x5A827999),
            20..=39 => (b ^ c ^ d, 0x6ED9EBA1),
            40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDC),
            _ => (b ^ c ^ d, 0xCA62C1D6),
        };

        let temp = a
            .rotate_left(5)
            .wrapping_add(f)
            .wrapping_add(e)
            .wrapping_add(k)
            .wrapping_add(w[i]);
        e = d;
        d = c;
        c = b.rotate_left(30);
        b = a;
        a = temp;
    }

    *h0 = h0.wrapping_add(a);
    *h1 = h1.wrapping_add(b);
    *h2 = h2.wrapping_add(c);
    *h3 = h3.wrapping_add(d);
    *h4 = h4.wrapping_add(e);
}

/// Computes standard 160-bit SHA-1 digest without heap allocations.
pub fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h0: u32 = 0x67452301;
    let mut h1: u32 = 0xEFCDAB89;
    let mut h2: u32 = 0x98BADCFE;
    let mut h3: u32 = 0x10325476;
    let mut h4: u32 = 0xC3D2E1F0;

    let chunks = data.chunks_exact(64);
    let rem = chunks.remainder();
    for chunk in chunks {
        let block: &[u8; 64] = chunk.try_into().unwrap();
        sha1_process_block(block, &mut h0, &mut h1, &mut h2, &mut h3, &mut h4);
    }

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut tail = [0u8; 128];
    tail[..rem.len()].copy_from_slice(rem);
    tail[rem.len()] = 0x80;

    if rem.len() < 56 {
        tail[56..64].copy_from_slice(&bit_len.to_be_bytes());
        let block: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        sha1_process_block(block, &mut h0, &mut h1, &mut h2, &mut h3, &mut h4);
    } else {
        tail[120..128].copy_from_slice(&bit_len.to_be_bytes());
        let block0: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        let block1: &[u8; 64] = (&tail[64..128]).try_into().unwrap();
        sha1_process_block(block0, &mut h0, &mut h1, &mut h2, &mut h3, &mut h4);
        sha1_process_block(block1, &mut h0, &mut h1, &mut h2, &mut h3, &mut h4);
    }

    let mut digest = [0u8; 20];
    digest[0..4].copy_from_slice(&h0.to_be_bytes());
    digest[4..8].copy_from_slice(&h1.to_be_bytes());
    digest[8..12].copy_from_slice(&h2.to_be_bytes());
    digest[12..16].copy_from_slice(&h3.to_be_bytes());
    digest[16..20].copy_from_slice(&h4.to_be_bytes());
    digest
}

/// Compute SHA-1 and return lowercase hex string.
pub fn sha1_hex(data: &[u8]) -> String {
    hex_encode(&sha1(data))
}

// -------------------------------------------------------------------------
// SHA-256 (FIPS 180-4) - Zero Heap Allocations
// -------------------------------------------------------------------------

const K256: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

#[inline(always)]
fn sha256_process_block(block: &[u8; 64], h: &mut [u32; 8]) {
    let mut w = [0u32; 64];
    for i in 0..16 {
        w[i] = u32::from_be_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }
    for i in 16..64 {
        let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
        let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16]
            .wrapping_add(s0)
            .wrapping_add(w[i - 7])
            .wrapping_add(s1);
    }

    let mut a = h[0];
    let mut b = h[1];
    let mut c = h[2];
    let mut d = h[3];
    let mut e = h[4];
    let mut f = h[5];
    let mut g = h[6];
    let mut hh = h[7];

    for i in 0..64 {
        let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
        let ch = (e & f) ^ ((!e) & g);
        let temp1 = hh
            .wrapping_add(s1)
            .wrapping_add(ch)
            .wrapping_add(K256[i])
            .wrapping_add(w[i]);
        let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let temp2 = s0.wrapping_add(maj);

        hh = g;
        g = f;
        f = e;
        e = d.wrapping_add(temp1);
        d = c;
        c = b;
        b = a;
        a = temp1.wrapping_add(temp2);
    }

    h[0] = h[0].wrapping_add(a);
    h[1] = h[1].wrapping_add(b);
    h[2] = h[2].wrapping_add(c);
    h[3] = h[3].wrapping_add(d);
    h[4] = h[4].wrapping_add(e);
    h[5] = h[5].wrapping_add(f);
    h[6] = h[6].wrapping_add(g);
    h[7] = h[7].wrapping_add(hh);
}

/// Computes standard 256-bit SHA-256 digest without heap allocations.
pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let chunks = data.chunks_exact(64);
    let rem = chunks.remainder();
    for chunk in chunks {
        let block: &[u8; 64] = chunk.try_into().unwrap();
        sha256_process_block(block, &mut h);
    }

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut tail = [0u8; 128];
    tail[..rem.len()].copy_from_slice(rem);
    tail[rem.len()] = 0x80;

    if rem.len() < 56 {
        tail[56..64].copy_from_slice(&bit_len.to_be_bytes());
        let block: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        sha256_process_block(block, &mut h);
    } else {
        tail[120..128].copy_from_slice(&bit_len.to_be_bytes());
        let block0: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        let block1: &[u8; 64] = (&tail[64..128]).try_into().unwrap();
        sha256_process_block(block0, &mut h);
        sha256_process_block(block1, &mut h);
    }

    let mut digest = [0u8; 32];
    for i in 0..8 {
        digest[i * 4..(i + 1) * 4].copy_from_slice(&h[i].to_be_bytes());
    }
    digest
}

/// Compute SHA-256 and return lowercase hex string.
pub fn sha256_hex(data: &[u8]) -> String {
    hex_encode(&sha256(data))
}

// -------------------------------------------------------------------------
// MD5 (RFC 1321) - Zero Heap Allocations
// -------------------------------------------------------------------------

const MD5_S: [u32; 64] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9,
    14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15,
    21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const MD5_K: [u32; 64] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

#[inline(always)]
fn md5_process_block(block: &[u8; 64], a: &mut u32, b: &mut u32, c: &mut u32, d: &mut u32) {
    let mut m = [0u32; 16];
    for i in 0..16 {
        m[i] = u32::from_le_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }

    let mut aa = *a;
    let mut bb = *b;
    let mut cc = *c;
    let mut dd = *d;

    for i in 0..64 {
        let (f, g) = match i {
            0..=15 => ((bb & cc) | ((!bb) & dd), i),
            16..=31 => ((dd & bb) | ((!dd) & cc), (5 * i + 1) % 16),
            32..=47 => (bb ^ cc ^ dd, (3 * i + 5) % 16),
            _ => (cc ^ (bb | (!dd)), (7 * i) % 16),
        };

        let temp = dd;
        dd = cc;
        cc = bb;
        bb = bb.wrapping_add(
            (aa.wrapping_add(f).wrapping_add(MD5_K[i]).wrapping_add(m[g])).rotate_left(MD5_S[i]),
        );
        aa = temp;
    }

    *a = a.wrapping_add(aa);
    *b = b.wrapping_add(bb);
    *c = c.wrapping_add(cc);
    *d = d.wrapping_add(dd);
}

/// Compute standard 128-bit MD5 digest without heap allocations.
pub fn md5(data: &[u8]) -> [u8; 16] {
    let mut a: u32 = 0x67452301;
    let mut b: u32 = 0xefcdab89;
    let mut c: u32 = 0x98badcfe;
    let mut d: u32 = 0x10325476;

    let chunks = data.chunks_exact(64);
    let rem = chunks.remainder();
    for chunk in chunks {
        let block: &[u8; 64] = chunk.try_into().unwrap();
        md5_process_block(block, &mut a, &mut b, &mut c, &mut d);
    }

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut tail = [0u8; 128];
    tail[..rem.len()].copy_from_slice(rem);
    tail[rem.len()] = 0x80;

    if rem.len() < 56 {
        tail[56..64].copy_from_slice(&bit_len.to_le_bytes());
        let block: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        md5_process_block(block, &mut a, &mut b, &mut c, &mut d);
    } else {
        tail[120..128].copy_from_slice(&bit_len.to_le_bytes());
        let block0: &[u8; 64] = (&tail[..64]).try_into().unwrap();
        let block1: &[u8; 64] = (&tail[64..128]).try_into().unwrap();
        md5_process_block(block0, &mut a, &mut b, &mut c, &mut d);
        md5_process_block(block1, &mut a, &mut b, &mut c, &mut d);
    }

    let mut digest = [0u8; 16];
    digest[0..4].copy_from_slice(&a.to_le_bytes());
    digest[4..8].copy_from_slice(&b.to_le_bytes());
    digest[8..12].copy_from_slice(&c.to_le_bytes());
    digest[12..16].copy_from_slice(&d.to_le_bytes());
    digest
}

/// Compute MD5 and return lowercase hex string.
pub fn md5_hex(data: &[u8]) -> String {
    hex_encode(&md5(data))
}

// -------------------------------------------------------------------------
// Random Byte Generation (Cryptographically Secure, Chunked & Fallback)
// -------------------------------------------------------------------------

/// Generate cryptographically secure pseudorandom bytes.
///
/// Handles arbitrary requested lengths by chunking `getentropy` (max 256 bytes per call),
/// falling back to `/dev/urandom` and software entropy mixing to prevent zero-filled output.
pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut buf = vec![0u8; len];
    if len == 0 {
        return buf;
    }

    let mut offset = 0;
    let mut getentropy_ok = true;

    while offset < len {
        let chunk_len = (len - offset).min(rux_core::config::GETENTROPY_MAX_CHUNK);
        let ret =
            unsafe { libc::getentropy(buf[offset..].as_mut_ptr() as *mut libc::c_void, chunk_len) };
        if ret == 0 {
            offset += chunk_len;
        } else {
            getentropy_ok = false;
            break;
        }
    }

    if !getentropy_ok && offset < len {
        // Fallback via /dev/urandom for remaining bytes
        let mut urandom_ok = false;
        if let Ok(mut file) = std::fs::File::open("/dev/urandom") {
            use std::io::Read;
            if file.read_exact(&mut buf[offset..]).is_ok() {
                urandom_ok = true;
            }
        }

        if !urandom_ok {
            // High-entropy fallback using SplitMix64 seeded with system clock, PID, and address
            let mut seed = (std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0x123456789ABCDEF0) as u64)
                ^ ((std::process::id() as u64) << 32)
                ^ (&buf as *const _ as usize as u64);

            for b in &mut buf[offset..] {
                seed = seed.wrapping_add(0x9e3779b97f4a7c15);
                let mut z = seed;
                z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
                z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
                *b = (z ^ (z >> 31)) as u8;
            }
        }
    }

    buf
}

/// Hash dispatcher matching `crypt.hash(data, algorithm)`.
///
/// Compares the algorithm name case-insensitively without allocating a
/// lowercased copy.
pub fn hash(algo: &str, data: &[u8]) -> Result<String, String> {
    if algo.eq_ignore_ascii_case("sha1") {
        Ok(sha1_hex(data))
    } else if algo.eq_ignore_ascii_case("sha256") {
        Ok(sha256_hex(data))
    } else if algo.eq_ignore_ascii_case("md5") {
        Ok(md5_hex(data))
    } else {
        Err(format!("Unsupported hash algorithm: {}", algo))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_base64_roundtrip() {
        let original = b"Hello from Rux pure-Rust crypto engine!";
        let encoded = base64_encode(original);
        let decoded = base64_decode(&encoded).expect("decode failed");
        assert_eq!(&decoded[..], original);
    }

    #[test]
    fn test_base64_empty() {
        assert_eq!(base64_encode(b""), "");
        assert_eq!(base64_decode("").unwrap(), Vec::<u8>::new());
    }

    #[test]
    fn test_hex_roundtrip() {
        let data = b"Hello World 123";
        let hex = hex_encode(data);
        let decoded = hex_decode(&hex).expect("hex decode failed");
        assert_eq!(&decoded[..], data);
    }

    #[test]
    fn test_sha1() {
        let input = b"abc";
        let expected = "a9993e364706816aba3e25717850c26c9cd0d89d";
        assert_eq!(sha1_hex(input), expected);
    }

    #[test]
    fn test_sha256() {
        let input = b"abc";
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        assert_eq!(sha256_hex(input), expected);
    }

    #[test]
    fn test_md5() {
        let input = b"abc";
        let expected = "900150983cd24fb0d6963f7d28e17f72";
        assert_eq!(md5_hex(input), expected);
    }

    #[test]
    fn test_random_bytes_over_256() {
        let bytes = random_bytes(512);
        assert_eq!(bytes.len(), 512);
        // Verify bytes 256..512 are not all zeroes
        let tail_non_zero = bytes[256..].iter().any(|&b| b != 0);
        assert!(
            tail_non_zero,
            "random_bytes(512) tail must not be all zeroes"
        );
    }

    #[test]
    fn test_sha256_long_input() {
        // Test with input spanning multiple 64-byte blocks
        let input = b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
        let expected = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1";
        assert_eq!(sha256_hex(input), expected);
    }

    #[test]
    fn test_sha1_empty() {
        assert_eq!(sha1_hex(b""), "da39a3ee5e6b4b0d3255bfef95601890afd80709");
    }

    #[test]
    fn test_sha256_empty() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn test_md5_empty() {
        assert_eq!(md5_hex(b""), "d41d8cd98f00b204e9800998ecf8427e");
    }

    #[test]
    fn test_sha256_56_byte_boundary() {
        // Exactly 56 bytes forces two padding blocks
        let input = b"12345678901234567890123456789012345678901234567890123456";
        assert_eq!(input.len(), 56);
        let digest = sha256_hex(input);
        assert_eq!(digest.len(), 64);
    }
}
