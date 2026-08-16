#include <metal_stdlib>
using namespace metal;

constant ulong K[80] = {
0x428a2f98d728ae22UL,0x7137449123ef65cdUL,0xb5c0fbcfec4d3b2fUL,0xe9b5dba58189dbbcUL,
0x3956c25bf348b538UL,0x59f111f1b605d019UL,0x923f82a4af194f9bUL,0xab1c5ed5da6d8118UL,
0xd807aa98a3030242UL,0x12835b0145706fbeUL,0x243185be4ee4b28cUL,0x550c7dc3d5ffb4e2UL,
0x72be5d74f27b896fUL,0x80deb1fe3b1696b1UL,0x9bdc06a725c71235UL,0xc19bf174cf692694UL,
0xe49b69c19ef14ad2UL,0xefbe4786384f25e3UL,0x0fc19dc68b8cd5b5UL,0x240ca1cc77ac9c65UL,
0x2de92c6f592b0275UL,0x4a7484aa6ea6e483UL,0x5cb0a9dcbd41fbd4UL,0x76f988da831153b5UL,
0x983e5152ee66dfabUL,0xa831c66d2db43210UL,0xb00327c898fb213fUL,0xbf597fc7beef0ee4UL,
0xc6e00bf33da88fc2UL,0xd5a79147930aa725UL,0x06ca6351e003826fUL,0x142929670a0e6e70UL,
0x27b70a8546d22ffcUL,0x2e1b21385c26c926UL,0x4d2c6dfc5ac42aedUL,0x53380d139d95b3dfUL,
0x650a73548baf63deUL,0x766a0abb3c77b2a8UL,0x81c2c92e47edaee6UL,0x92722c851482353bUL,
0xa2bfe8a14cf10364UL,0xa81a664bbc423001UL,0xc24b8b70d0f89791UL,0xc76c51a30654be30UL,
0xd192e819d6ef5218UL,0xd69906245565a910UL,0xf40e35855771202aUL,0x106aa07032bbd1b8UL,
0x19a4c116b8d2d0c8UL,0x1e376c085141ab53UL,0x2748774cdf8eeb99UL,0x34b0bcb5e19b48a8UL,
0x391c0cb3c5c95a63UL,0x4ed8aa4ae3418acbUL,0x5b9cca4f7763e373UL,0x682e6ff3d6b2b8a3UL,
0x748f82ee5defb2fcUL,0x78a5636f43172f60UL,0x84c87814a1f0ab72UL,0x8cc702081a6439ecUL,
0x90befffa23631e28UL,0xa4506cebde82bde9UL,0xbef9a3f7b2c67915UL,0xc67178f2e372532bUL,
0xca273eceea26619cUL,0xd186b8c721c0c207UL,0xeada7dd6cde0eb1eUL,0xf57d4f7fee6ed178UL,
0x06f067aa72176fbaUL,0x0a637dc5a2c898a6UL,0x113f9804bef90daeUL,0x1b710b35131c471bUL,
0x28db77f523047d84UL,0x32caab7b40c72493UL,0x3c9ebe0a15c9bebcUL,0x431d67c49c100d4cUL,
0x4cc5d4becb3e42b6UL,0x597f299cfc657e2aUL,0x5fcb6fab3ad6faecUL,0x6c44198c4a475817UL};

inline ulong rr(ulong x, uint n) { return (x >> n) | (x << (64-n)); }
inline ulong loadbe(thread const uchar *p) {
    ulong v=0; for(uint i=0;i<8;i++) v=(v<<8)|p[i]; return v;
}
inline void storebe(thread uchar *p, ulong v) {
    for(int i=7;i>=0;i--){ p[i]=uchar(v); v>>=8; }
}
inline void sha512_one(thread const uchar *msg, uint len, thread ulong *out) {
    ulong w[80];
    uchar block[128];
    for(uint i=0;i<128;i++) block[i]=0;
    for(uint i=0;i<len;i++) block[i]=msg[i];
    block[len]=0x80;
    ulong bits=ulong(len)*8UL;
    for(uint i=0;i<8;i++) block[127-i]=uchar(bits>>(8*i));
    for(uint i=0;i<16;i++) w[i]=loadbe(block+i*8);
    for(uint i=16;i<80;i++) {
        ulong s0=rr(w[i-15],1)^rr(w[i-15],8)^(w[i-15]>>7);
        ulong s1=rr(w[i-2],19)^rr(w[i-2],61)^(w[i-2]>>6);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    ulong a=0x6a09e667f3bcc908UL,b=0xbb67ae8584caa73bUL,c=0x3c6ef372fe94f82bUL,d=0xa54ff53a5f1d36f1UL;
    ulong e=0x510e527fade682d1UL,f=0x9b05688c2b3e6c1fUL,g=0x1f83d9abfb41bd6bUL,h=0x5be0cd19137e2179UL;
    for(uint i=0;i<80;i++) {
        ulong S1=rr(e,14)^rr(e,18)^rr(e,41), ch=(e&f)^((~e)&g);
        ulong t1=h+S1+ch+K[i]+w[i];
        ulong S0=rr(a,28)^rr(a,34)^rr(a,39), maj=(a&b)^(a&c)^(b&c);
        ulong t2=S0+maj;
        h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    out[0]=a+0x6a09e667f3bcc908UL; out[1]=b+0xbb67ae8584caa73bUL;
    out[2]=c+0x3c6ef372fe94f82bUL; out[3]=d+0xa54ff53a5f1d36f1UL;
    out[4]=e+0x510e527fade682d1UL; out[5]=f+0x9b05688c2b3e6c1fUL;
    out[6]=g+0x1f83d9abfb41bd6bUL; out[7]=h+0x5be0cd19137e2179UL;
}

kernel void office2013_kdf(
    device const uchar *passwords [[buffer(0)]],
    device const uint *lengths [[buffer(1)]],
    constant uchar *salt [[buffer(2)]],
    constant uint &spinCount [[buffer(3)]],
    device ulong *results [[buffer(4)]],
    uint gid [[thread_position_in_grid]]) {
    uint length=lengths[gid]; if(length>64) return;
    uchar message[80];
    for(uint i=0;i<16;i++) message[i]=salt[i];
    for(uint i=0;i<length;i++) message[16+i]=passwords[gid*64+i];
    ulong digest[8]; sha512_one(message,16+length,digest);
    uchar iteration[68];
    for(uint round=0;round<spinCount;round++) {
        iteration[0]=uchar(round); iteration[1]=uchar(round>>8);
        iteration[2]=uchar(round>>16); iteration[3]=uchar(round>>24);
        for(uint i=0;i<8;i++) storebe(iteration+4+i*8,digest[i]);
        sha512_one(iteration,68,digest);
    }
    for(uint i=0;i<8;i++) results[gid*8+i]=digest[i];
}
