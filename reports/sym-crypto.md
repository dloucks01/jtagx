# Symbol-guided crypto scan — 160 crypto/credential-named globals (16777216 byte dump, base mapping VA-0xffffffff80100000)

Each crypto-named global read at its mapped address. **AES keys are validated** (key-schedule math); high-entropy = likely key material; verify before acting.

summary: 95 entropy, 6 string, 57 data, 2 zero

- **[HIGH-ENTROPY]** `randomInit`  VA=0xffffffff80103f94  off=0x3f94
    high-entropy (H=4.76/8 over a key-sized window) — likely key/secret material
    `fd 7b bf a9 fd 03 00 91 d9 8f 0a 94 e0 03 18 32 01 8f 0a 94 e0 03 18 32 fd 7b c1 a8 16 8f 0a 14`
- **[HIGH-ENTROPY]** `avlTree_Delete_From_Key`  VA=0xffffffff801298e4  off=0x298e4
    high-entropy (H=4.64/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 13 00 40 f9 fd 83 00 91 53 02 00 b4 f4 03 00 aa f5 03 01 aa`
- **[HIGH-ENTROPY]** `_ZN11coeEndpoint11autoDecryptEj`  VA=0xffffffff8012aae0  off=0x2aae0
    high-entropy (H=4.66/8 over a key-sized window) — likely key/secret material
    `00 04 40 f9 40 00 00 b4 1e 0a 00 14 e0 03 1f 32 c0 03 5f d6 f4 4f be a9 fd 7b 01 a9 fd 43 00 91`
- **[HIGH-ENTROPY]** `_ZN10coeMessage11setDefaultsEP12coeEncryptorS1_jj`  VA=0xffffffff8012b4ec  off=0x2b4ec
    high-entropy (H=4.35/8 over a key-sized window) — likely key/secret material
    `40 00 00 b4 00 04 40 f9 41 00 00 b4 21 04 40 f9 82 0b 00 14 f3 0f 1e f8 fd 7b 01 a9 fd 43 00 91`
- **[HIGH-ENTROPY]** `OE_Endpoint_Auto_Decrypt`  VA=0xffffffff8012d360  off=0x2d360
    high-entropy (H=4.68/8 over a key-sized window) — likely key/secret material
    `e0 01 00 b4 09 00 40 b9 ca 59 9f 52 ea dd b7 72 e8 03 00 aa 3f 01 0a 6b 61 01 00 54 09 41 40 b9`
- **[HIGH-ENTROPY]** `OE_Message_Decrypt`  VA=0xffffffff8012dd04  off=0x2dd04
    high-entropy (H=4.91/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 fd 7b 01 a9 fd 43 00 91 60 01 00 b4 08 00 40 b9 c9 59 9f 52 e9 dd b7 72 f3 03 00 aa`
- **[HIGH-ENTROPY]** `OE_Message_get_Encrypted_Buffer_Address`  VA=0xffffffff8012de00  off=0x2de00
    high-entropy (H=4.88/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 f4 4f 01 a9 f4 03 02 aa fd 7b 02 a9 fd 83 00 91 e0 01 00 b4 08 00 40 b9 c9 59 9f 52`
- **[HIGH-ENTROPY]** `OE_Message_Encrypt`  VA=0xffffffff8012de84  off=0x2de84
    high-entropy (H=4.98/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 fd c3 00 91 60 01 00 b4 08 00 40 b9 c9 59 9f 52`
- **[HIGH-ENTROPY]** `OE_Encryptor_Create`  VA=0xffffffff80130bf0  off=0x30bf0
    high-entropy (H=4.38/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 bf 00 00 b9 08 00 40 b9 f7 03 01 aa f5 03 00 aa`
- **[HIGH-ENTROPY]** `OE_Encryptor_Delete`  VA=0xffffffff80130c80  off=0x30c80
    high-entropy (H=4.80/8 over a key-sized window) — likely key/secret material
    `a0 01 00 b4 08 00 40 b9 c9 59 9f 52 e9 dd b7 72 1f 01 09 6b 41 01 00 54 fd 7b bf a9 fd 03 00 91`
- **[HIGH-ENTROPY]** `OE_Encryptor_Set_Key`  VA=0xffffffff80130cc4  off=0x30cc4
    high-entropy (H=4.93/8 over a key-sized window) — likely key/secret material
    `f8 5f bc a9 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 fd c3 00 91 e0 03 00 b4 08 00 40 b9 c9 59 9f 52`
- **[HIGH-ENTROPY]** `OE_Encryptor_Get_Data_Size`  VA=0xffffffff80130d70  off=0x30d70
    high-entropy (H=4.83/8 over a key-sized window) — likely key/secret material
    `ff c3 00 d1 f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 ff 0f 00 b9 a0 02 00 b4 08 00 40 b9 c9 59 9f 52`
- **[HIGH-ENTROPY]** `OE_Encryptor_Get_Block_Size`  VA=0xffffffff80130fe0  off=0x30fe0
    high-entropy (H=4.73/8 over a key-sized window) — likely key/secret material
    `e0 00 00 b4 08 00 40 b9 c9 59 9f 52 e9 dd b7 72 1f 01 09 6b 61 00 00 54 00 34 40 b9 c0 03 5f d6`
- **[HIGH-ENTROPY]** `OE_Encryptor_Execute`  VA=0xffffffff80131008  off=0x31008
    high-entropy (H=4.96/8 over a key-sized window) — likely key/secret material
    `fa 67 bb a9 f8 5f 01 a9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 fd 03 01 91 e0 02 00 b4 08 00 40 b9`
- **[HIGH-ENTROPY]** `secHashMd5OpensslTemplateGet`  VA=0xffffffff8022c0e0  off=0x12c0e0
    high-entropy (H=4.40/8 over a key-sized window) — likely key/secret material
    `a0 40 00 f0 00 c0 09 91 c0 03 5f d6 a0 40 00 f0 00 c0 09 91 f7 8b 01 14 f3 0f 1e f8 f3 03 00 aa`
- **[HIGH-ENTROPY]** `secHashMd5OpensslInit`  VA=0xffffffff8022c0ec  off=0x12c0ec
    high-entropy (H=4.58/8 over a key-sized window) — likely key/secret material
    `a0 40 00 f0 00 c0 09 91 f7 8b 01 14 f3 0f 1e f8 f3 03 00 aa 00 00 80 12 fd 7b 01 a9 fd 43 00 91`
- **[HIGH-ENTROPY]** `secHashSha1OpensslInit`  VA=0xffffffff8022c26c  off=0x12c26c
    high-entropy (H=4.46/8 over a key-sized window) — likely key/secret material
    `a0 2e 00 f0 00 20 3b 91 9d 8b 01 14 a0 2e 00 f0 00 20 3b 91 c0 03 5f d6 f3 0f 1e f8 f3 03 00 aa`
- **[HIGH-ENTROPY]** `secHashSha1OpensslTemplateGet`  VA=0xffffffff8022c278  off=0x12c278
    high-entropy (H=4.71/8 over a key-sized window) — likely key/secret material
    `a0 2e 00 f0 00 20 3b 91 c0 03 5f d6 f3 0f 1e f8 f3 03 00 aa 00 00 80 12 fd 7b 01 a9 fd 43 00 91`
- **[HIGH-ENTROPY]** `secHashSha256OpensslInit`  VA=0xffffffff8022c3f8  off=0x12c3f8
    high-entropy (H=4.46/8 over a key-sized window) — likely key/secret material
    `a0 2e 00 f0 00 20 3c 91 40 8b 01 14 a0 2e 00 f0 00 20 3c 91 c0 03 5f d6 f3 0f 1e f8 f3 03 00 aa`
- **[HIGH-ENTROPY]** `secHashSha256OpensslTemplateGet`  VA=0xffffffff8022c404  off=0x12c404
    high-entropy (H=4.71/8 over a key-sized window) — likely key/secret material
    `a0 2e 00 f0 00 20 3c 91 c0 03 5f d6 f3 0f 1e f8 f3 03 00 aa 00 00 80 12 fd 7b 01 a9 fd 43 00 91`
- **[HIGH-ENTROPY]** `SHA1_Update`  VA=0xffffffff8022d250  off=0x12d250
    high-entropy (H=4.77/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 fd c3 00 91 22 07 00 b4 08 a4 42 29 f3 03 02 aa`
- **[HIGH-ENTROPY]** `SHA1_Transform`  VA=0xffffffff8022d360  off=0x12d360
    high-entropy (H=4.83/8 over a key-sized window) — likely key/secret material
    `e2 03 00 32 47 02 00 14 f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 28 5c 40 b9 35 70 00 91 e9 03 19 32`
- **[HIGH-ENTROPY]** `SHA1_Final`  VA=0xffffffff8022d368  off=0x12d368
    high-entropy (H=4.84/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 28 5c 40 b9 35 70 00 91 e9 03 19 32 f4 03 01 aa f3 03 00 aa`
- **[HIGH-ENTROPY]** `SHA1_Init`  VA=0xffffffff8022d4e8  off=0x12d4e8
    high-entropy (H=5.19/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 e2 07 1b 32 e1 03 1f 2a fd 7b 01 a9 fd 43 00 91 f3 03 00 aa b7 e9 01 94 28 60 84 d2`
- **[HIGH-ENTROPY]** `SHA224_Init`  VA=0xffffffff8022d544  off=0x12d544
    high-entropy (H=5.08/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 e2 0b 1c 32 e1 03 1f 2a fd 7b 01 a9 fd 43 00 91 f3 03 00 aa a0 e9 01 94 08 db 93 d2`
- **[HIGH-ENTROPY]** `SHA256_Init`  VA=0xffffffff8022d5c0  off=0x12d5c0
    high-entropy (H=5.21/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 e2 0b 1c 32 e1 03 1f 2a fd 7b 01 a9 fd 43 00 91 f3 03 00 aa 81 e9 01 94 e8 cc 9c d2`
- **[HIGH-ENTROPY]** `SHA224`  VA=0xffffffff8022d63c  off=0x12d63c
    high-entropy (H=4.89/8 over a key-sized window) — likely key/secret material
    `ff 83 02 d1 e8 47 00 f0 08 65 24 91 5f 00 00 f1 f5 3b 00 f9 f4 4f 08 a9 f3 03 01 aa f4 03 00 aa`
- **[HIGH-ENTROPY]** `SHA256_Update`  VA=0xffffffff8022d708  off=0x12d708
    high-entropy (H=4.77/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 fd c3 00 91 22 07 00 b4 08 24 44 29 f3 03 02 aa`
- **[HIGH-ENTROPY]** `SHA256_Final`  VA=0xffffffff8022d818  off=0x12d818
    high-entropy (H=4.84/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 28 68 40 b9 35 a0 00 91 e9 03 19 32 f4 03 01 aa f3 03 00 aa`
- **[HIGH-ENTROPY]** `SHA256`  VA=0xffffffff8022db40  off=0x12db40
    high-entropy (H=4.89/8 over a key-sized window) — likely key/secret material
    `ff 83 02 d1 e8 47 00 f0 08 d5 24 91 5f 00 00 f1 f5 3b 00 f9 f4 4f 08 a9 f3 03 01 aa f4 03 00 aa`
- **[HIGH-ENTROPY]** `SHA224_Update`  VA=0xffffffff8022dc0c  off=0x12dc0c
    high-entropy (H=4.60/8 over a key-sized window) — likely key/secret material
    `fd 7b bf a9 fd 03 00 91 bd fe ff 97 e0 03 00 32 fd 7b c1 a8 c0 03 5f d6 fd fe ff 17 e2 03 00 32`
- **[HIGH-ENTROPY]** `SHA224_Final`  VA=0xffffffff8022dc24  off=0x12dc24
    high-entropy (H=4.38/8 over a key-sized window) — likely key/secret material
    `fd fe ff 17 e2 03 00 32 c5 04 00 14 a8 40 00 d0 03 59 41 f9 e2 03 01 aa e1 03 1f 2a 60 00 1f d6`
- **[HIGH-ENTROPY]** `sha1_block_data_order`  VA=0xffffffff8022dc80  off=0x12dc80
    high-entropy (H=4.72/8 over a key-sized window) — likely key/secret material
    `10 92 00 58 f1 91 00 10 10 02 11 8b 10 02 40 b9 1f 02 1d 72 61 7f 00 54 fd 7b ba a9 fd 03 00 91`
- **[HIGH-ENTROPY]** `sha256_block_data_order`  VA=0xffffffff8022ef40  off=0x12ef40
    high-entropy (H=4.79/8 over a key-sized window) — likely key/secret material
    `50 7a 00 58 31 7a 00 10 10 02 11 8b 10 02 40 b9 1f 02 1c 72 61 7d 00 54 fd 7b b8 a9 fd 03 00 91`
- **[HIGH-ENTROPY]** `OPENSSL_rdtsc`  VA=0xffffffff802300ec  off=0x1300ec
    high-entropy (H=4.93/8 over a key-sized window) — likely key/secret material
    `e8 47 00 90 08 61 65 39 68 00 08 37 e0 03 1f aa c0 03 5f d6 a2 00 00 14 ff 83 01 d1 e8 47 00 90`
- **[HIGH-ENTROPY]** `OPENSSL_cpuid_setup`  VA=0xffffffff80230104  off=0x130104
    high-entropy (H=4.89/8 over a key-sized window) — likely key/secret material
    `ff 83 01 d1 e8 47 00 90 09 71 65 39 f5 1b 00 f9 f4 4f 04 a9 fd 7b 05 a9 fd 43 01 91 e9 10 00 37`
- **[HIGH-ENTROPY]** `ipcom_cmd_key_to_str`  VA=0xffffffff80230dec  off=0x130dec
    high-entropy (H=4.63/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 fd 7b 01 a9 0a 00 40 b9 f3 03 02 aa e8 03 01 2a fd 43 00 91 5f 05 00 31 e0 00 00 54`
- **[HIGH-ENTROPY]** `ipcom_cmd_str_to_key`  VA=0xffffffff80230e58  off=0x130e58
    high-entropy (H=4.43/8 over a key-sized window) — likely key/secret material
    `f4 4f be a9 fd 7b 01 a9 fd 43 00 91 61 01 00 b4 f4 03 01 aa 01 04 40 f9 f3 03 00 aa e1 00 00 b4`
- **[HIGH-ENTROPY]** `ipcom_cmd_str_to_key2`  VA=0xffffffff80230ea8  off=0x130ea8
    high-entropy (H=4.44/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 81 01 00 b4 f5 03 01 aa 01 04 40 f9 f4 03 00 aa`
- **[HIGH-ENTROPY]** `ipcom_random_init`  VA=0xffffffff80237998  off=0x137998
    high-entropy (H=4.48/8 over a key-sized window) — likely key/secret material
    `ff 03 01 d1 e8 53 00 91 e0 63 00 91 e1 03 1f aa fd 7b 03 a9 fd c3 00 91 e8 07 00 f9 ed 0c 00 94`
- **[HIGH-ENTROPY]** `ipcom_srandom`  VA=0xffffffff80237a08  off=0x137a08
    high-entropy (H=4.52/8 over a key-sized window) — likely key/secret material
    `ff 83 00 d1 fd 7b 01 a9 fd 43 00 91 a0 c3 1f b8 a0 13 00 d1 e1 03 1e 32 e2 03 00 32 ea c0 05 94`
- **[HIGH-ENTROPY]** `ipcom_random`  VA=0xffffffff80237a34  off=0x137a34
    high-entropy (H=4.52/8 over a key-sized window) — likely key/secret material
    `ff 83 00 d1 fd 7b 01 a9 fd 43 00 91 a0 13 00 d1 e1 03 1e 32 d5 c0 05 94 a0 c3 5f b8 fd 7b 41 a9`
- **[HIGH-ENTROPY]** `ipcom_random_seed_state`  VA=0xffffffff80237ac0  off=0x137ac0
    high-entropy (H=4.93/8 over a key-sized window) — likely key/secret material
    `fd 7b bf a9 fd 03 00 91 c7 c0 05 94 08 78 1f 12 1f 09 00 71 88 0c 80 52 00 01 9f 1a fd 7b c1 a8`
- **[HIGH-ENTROPY]** `ipnet_route_key_to_sockaddr`  VA=0xffffffff80266fb0  off=0x166fb0
    high-entropy (H=4.59/8 over a key-sized window) — likely key/secret material
    `f6 57 bd a9 f4 4f 01 a9 f3 03 02 aa f4 03 00 2a 1f 08 00 71 fd 7b 02 a9 fd 83 00 91 81 01 00 54`
- **[HIGH-ENTROPY]** `ipnet_route_sockaddr_to_key`  VA=0xffffffff80268804  off=0x168804
    high-entropy (H=4.83/8 over a key-sized window) — likely key/secret material
    `1f 08 00 71 c1 00 00 54 e8 03 02 aa 21 10 00 91 e2 03 1e 32 e0 03 08 aa 50 fc 00 14 c0 03 5f d6`
- **[HIGH-ENTROPY]** `ipnet_route_key_cmp`  VA=0xffffffff80269c70  off=0x169c70
    high-entropy (H=4.67/8 over a key-sized window) — likely key/secret material
    `f6 57 bd a9 f6 03 02 2a d5 1e 43 d3 e2 03 15 aa f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 f3 03 01 aa`
- **[HIGH-ENTROPY]** `ipnet_rtnetlink_ip4_route_key_setup`  VA=0xffffffff8026d288  off=0x16d288
    high-entropy (H=4.58/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f4 4f 02 a9 f3 03 02 aa e2 03 1d 32 e1 03 1f 2a f6 57 01 a9 fd 7b 03 a9 fd c3 00 91`
- **[HIGH-ENTROPY]** `ipnet_rtnetlink_route_key_setup`  VA=0xffffffff8026f1dc  off=0x16f1dc
    high-entropy (H=4.69/8 over a key-sized window) — likely key/secret material
    `1f 08 00 71 81 01 00 54 fd 7b bf a9 e0 03 01 aa e1 03 02 2a e2 03 03 aa e3 03 04 2a e4 03 05 aa`
- **[HIGH-ENTROPY]** `secHashSha256TemplateGet`  VA=0xffffffff8028f0f4  off=0x18f0f4
    high-entropy (H=4.57/8 over a key-sized window) — likely key/secret material
    `e8 44 00 f0 00 0d 44 f9 c0 03 5f d6 e8 44 00 f0 00 0d 04 f9 c0 03 5f d6 ff 43 06 d1 fa 67 14 a9`
- **[HIGH-ENTROPY]** `secHashSha256TemplateSet`  VA=0xffffffff8028f100  off=0x18f100
    high-entropy (H=5.01/8 over a key-sized window) — likely key/secret material
    `e8 44 00 f0 00 0d 04 f9 c0 03 5f d6 ff 43 06 d1 fa 67 14 a9 f9 44 00 f0 28 23 48 b9 fc 6f 13 a9`
- **[HIGH-ENTROPY]** `taskTlsBaseSet`  VA=0xffffffff8029e05c  off=0x19e05c
    high-entropy (H=4.61/8 over a key-sized window) — likely key/secret material
    `a0 01 00 b4 e8 03 00 aa 3f 00 48 f1 83 01 00 54 29 fc 6b d3 49 01 00 b5 49 02 40 f9 3f 01 08 eb`
- **[HIGH-ENTROPY]** `xbdRequestHashKeyCmp`  VA=0xffffffff8029feb4  off=0x19feb4
    high-entropy (H=5.03/8 over a key-sized window) — likely key/secret material
    `5f 00 00 f1 08 0a 80 52 e9 07 1b 32 28 01 88 9a 09 68 68 f8 28 68 68 f8 3f 01 08 eb e0 17 9f 1a`
- **[HIGH-ENTROPY]** `seed48`  VA=0xffffffff802b2008  off=0x1b2008
    high-entropy (H=4.63/8 over a key-sized window) — likely key/secret material
    `08 08 40 79 09 04 40 79 0a 00 40 79 ac cd 9c d2 8c dd bb f2 e0 43 00 b0 ab 3c 00 b0 ac 00 c0 f2`
- **[HIGH-ENTROPY]** `hashKeyCmp`  VA=0xffffffff803002a0  off=0x2002a0
    high-entropy (H=4.39/8 over a key-sized window) — likely key/secret material
    `e8 03 00 aa e0 03 1f 2a c8 00 00 b4 a1 00 00 b4 08 05 40 f9 29 04 40 f9 1f 01 09 eb e0 17 9f 1a`
- **[HIGH-ENTROPY]** `hashKeyStrCmp`  VA=0xffffffff803002c4  off=0x2002c4
    high-entropy (H=4.59/8 over a key-sized window) — likely key/secret material
    `e8 03 00 aa e0 03 1f 2a 48 01 00 b4 21 01 00 b4 fd 7b bf a9 00 05 40 f9 21 04 40 f9 fd 03 00 91`
- **[HIGH-ENTROPY]** `rngCreate`  VA=0xffffffff80300bbc  off=0x200bbc
    high-entropy (H=4.49/8 over a key-sized window) — likely key/secret material
    `f4 4f be a9 f4 03 00 aa e0 03 1b 32 fd 7b 01 a9 fd 43 00 91 3c 9b fe 97 f3 03 00 aa 60 01 00 b4`
- **[HIGH-ENTROPY]** `rngFlush`  VA=0xffffffff80300c14  off=0x200c14
    high-entropy (H=4.81/8 over a key-sized window) — likely key/secret material
    `1f 7c 00 a9 c0 03 5f d6 f3 0f 1e f8 fd 7b 01 a9 f3 03 00 aa 00 0c 40 f9 fd 43 00 91 d0 99 fe 97`
- **[HIGH-ENTROPY]** `rngDelete`  VA=0xffffffff80300c1c  off=0x200c1c
    high-entropy (H=4.80/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 fd 7b 01 a9 f3 03 00 aa 00 0c 40 f9 fd 43 00 91 d0 99 fe 97 fd 7b 41 a9 e0 03 13 aa`
- **[HIGH-ENTROPY]** `rngBufGet`  VA=0xffffffff80300c44  off=0x200c44
    high-entropy (H=4.70/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 17 00 40 f9 bf 3d 03 d5 08 04 40 f9 f6 03 02 aa`
- **[HIGH-ENTROPY]** `rngBufPut`  VA=0xffffffff80300d20  off=0x200d20
    high-entropy (H=4.59/8 over a key-sized window) — likely key/secret material
    `f7 0f 1c f8 f6 57 01 a9 f4 4f 02 a9 fd 7b 03 a9 08 5c 40 a9 f6 03 02 aa f3 03 00 aa f5 03 01 aa`
- **[HIGH-ENTROPY]** `rngIsEmpty`  VA=0xffffffff80300e34  off=0x200e34
    high-entropy (H=4.38/8 over a key-sized window) — likely key/secret material
    `08 24 40 a9 1f 01 09 eb e0 17 9f 1a c0 03 5f d6 08 24 40 a9 08 01 09 cb 08 05 00 b1 a0 00 00 54`
- **[HIGH-ENTROPY]** `rngIsFull`  VA=0xffffffff80300e44  off=0x200e44
    high-entropy (H=4.49/8 over a key-sized window) — likely key/secret material
    `08 24 40 a9 08 01 09 cb 08 05 00 b1 a0 00 00 54 09 08 40 f9 1f 01 09 eb e0 17 9f 1a c0 03 5f d6`
- **[HIGH-ENTROPY]** `rngPutAhead`  VA=0xffffffff80300eb0  off=0x200eb0
    high-entropy (H=4.45/8 over a key-sized window) — likely key/secret material
    `08 00 40 f9 09 28 41 a9 08 01 02 8b 1f 01 09 eb e9 33 89 9a 08 01 09 cb 41 69 28 38 c0 03 5f d6`
- **[HIGH-ENTROPY]** `rngMoveAhead`  VA=0xffffffff80300ed0  off=0x200ed0
    high-entropy (H=4.37/8 over a key-sized window) — likely key/secret material
    `08 00 40 f9 09 08 40 f9 bf 3e 03 d5 08 01 01 8b 1f 01 09 eb e9 33 89 9a 08 01 09 cb 08 00 00 f9`
- **[HIGH-ENTROPY]** `_ZSt22_Random_device_entropyv`  VA=0xffffffff8032ed60  off=0x22ed60
    high-entropy (H=4.58/8 over a key-sized window) — likely key/secret material
    `e0 03 67 9e c0 03 5f d6 25 3d fe 17 fd 7b bf a9 fd 03 00 91 e8 40 00 90 08 01 2d 91 08 fd df 08`
- **[HIGH-ENTROPY]** `_ZSt14_Random_devicev`  VA=0xffffffff8032ed68  off=0x22ed68
    high-entropy (H=4.56/8 over a key-sized window) — likely key/secret material
    `25 3d fe 17 fd 7b bf a9 fd 03 00 91 e8 40 00 90 08 01 2d 91 08 fd df 08 68 00 00 36 fd 7b c1 a8`
- **[HIGH-ENTROPY]** `vxdbgBpUserKeySet`  VA=0xffffffff80362d4c  off=0x262d4c
    high-entropy (H=4.99/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 88 3e 00 90 08 01 5b 39 f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 88 03 00 36 f5 03 00 aa`
- **[HIGH-ENTROPY]** `vxdbgBpUserKeyGet`  VA=0xffffffff80362e20  off=0x262e20
    high-entropy (H=4.99/8 over a key-sized window) — likely key/secret material
    `f5 0f 1d f8 88 3e 00 90 08 01 5b 39 f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 88 03 00 36 f5 03 00 aa`
- **[HIGH-ENTROPY]** `tlsLoadLibInit`  VA=0xffffffff8038a5d8  off=0x28a5d8
    high-entropy (H=4.30/8 over a key-sized window) — likely key/secret material
    `69 02 00 d0 0b 00 00 90 6d 02 00 d0 60 02 00 d0 88 3e 00 d0 29 71 1d 91 8a 3e 00 d0 6b 51 18 91`
- **[HIGH-ENTROPY]** `pthread_key_create`  VA=0xffffffff803a0830  off=0x2a0830
    high-entropy (H=4.66/8 over a key-sized window) — likely key/secret material
    `f6 57 bd a9 f4 4f 01 a9 fd 7b 02 a9 fd 83 00 91 f3 03 01 aa f4 03 00 aa 69 ff ff 97 a4 f1 fb 97`
- **[HIGH-ENTROPY]** `pthread_key_delete`  VA=0xffffffff803a0a38  off=0x2a0a38
    high-entropy (H=4.72/8 over a key-sized window) — likely key/secret material
    `f4 4f be a9 1f fc 03 f1 fd 7b 01 a9 fd 43 00 91 c8 02 00 54 b4 3c 00 90 f3 03 00 aa 80 ee 44 f9`
- **[HIGH-ENTROPY]** `taskCredentialsInherit`  VA=0xffffffff803a2a24  off=0x2a2a24
    high-entropy (H=4.48/8 over a key-sized window) — likely key/secret material
    `c0 00 00 b4 48 02 40 f9 a8 01 00 b4 08 5d 42 f9 08 05 40 79 0b 00 00 14 fd 7b bf a9 fd 03 00 91`
- **[HIGH-ENTROPY]** `rtpCredentialsInherit`  VA=0xffffffff803a2b28  off=0x2a2b28
    high-entropy (H=4.51/8 over a key-sized window) — likely key/secret material
    `49 02 40 f9 c0 00 00 b4 48 02 40 f9 a8 01 00 b4 08 5d 42 f9 08 05 40 79 0b 00 00 14 fd 7b bf a9`
- **[HIGH-ENTROPY]** `randomEntropyAddSwitchHookInit`  VA=0xffffffff803a7c08  off=0x2a7c08
    high-entropy (H=4.51/8 over a key-sized window) — likely key/secret material
    `ff 03 02 d1 f3 33 00 f9 fd 7b 07 a9 fd c3 01 91 00 05 00 34 68 3c 00 d0 00 c5 0a b9 08 00 00 90`
- **[HIGH-ENTROPY]** `randomTsShow`  VA=0xffffffff803a7d50  off=0x2a7d50
    high-entropy (H=4.68/8 over a key-sized window) — likely key/secret material
    `68 3c 00 d0 69 3c 00 d0 01 c5 4a b9 22 c9 4a b9 a0 2b 00 90 00 d4 25 91 e2 4c fc 17 48 3d 00 90`
- **[HIGH-ENTROPY]** `randomSWNumGenInit`  VA=0xffffffff803a7f00  off=0x2a7f00
    high-entropy (H=4.99/8 over a key-sized window) — likely key/secret material
    `ff 43 01 d1 60 3c 00 d0 00 80 2b 91 e1 03 1f 2a fd 7b 04 a9 fd 03 01 91 bb 61 01 94 48 35 00 d0`
- **[HIGH-ENTROPY]** `randomAddTimeStamp`  VA=0xffffffff803a80ac  off=0x2a80ac
    high-entropy (H=4.94/8 over a key-sized window) — likely key/secret material
    `fd 7b bf a9 69 3c 00 b0 08 9d 3b d5 2a f9 4c b9 6b 3c 00 b0 6b c1 2b 91 60 3c 00 b0 6c 69 6a 38`
- **[HIGH-ENTROPY]** `shellInternalStrSpaceTokenize`  VA=0xffffffff803c0d74  off=0x2c0d74
    high-entropy (H=4.71/8 over a key-sized window) — likely key/secret material
    `f6 57 bd a9 f4 4f 01 a9 f3 03 01 aa f4 03 00 aa fd 7b 02 a9 fd 83 00 91 60 00 00 b5 74 02 40 f9`
- **[HIGH-ENTROPY]** `shellInternalStrTokenize`  VA=0xffffffff803c0e54  off=0x2c0e54
    high-entropy (H=4.54/8 over a key-sized window) — likely key/secret material
    `f6 57 bd a9 f4 4f 01 a9 f3 03 02 aa f5 03 01 aa f4 03 00 aa fd 7b 02 a9 fd 83 00 91 60 00 00 b5`
- **[HIGH-ENTROPY]** `absSymbols_Tls`  VA=0xffffffff803d8644  off=0x2d8644
    high-entropy (H=5.01/8 over a key-sized window) — likely key/secret material
    `e0 03 1f 2a c0 03 5f d6 f3 0f 1e f8 fd 7b 01 a9 f3 3a 00 d0 68 62 54 39 fd 43 00 91 c8 05 00 37`
- **[HIGH-ENTROPY]** `tlsLibInit`  VA=0xffffffff803d864c  off=0x2d864c
    high-entropy (H=4.92/8 over a key-sized window) — likely key/secret material
    `f3 0f 1e f8 fd 7b 01 a9 f3 3a 00 d0 68 62 54 39 fd 43 00 91 c8 05 00 37 bf 00 03 eb 6e 30 85 9a`
- **[HIGH-ENTROPY]** `tlsStdModuleAdd`  VA=0xffffffff803d875c  off=0x2d875c
    high-entropy (H=4.71/8 over a key-sized window) — likely key/secret material
    `fc 6f ba a9 fa 67 01 a9 99 04 00 d1 28 03 03 8b fb 03 04 cb 08 01 1b 8a f8 5f 02 a9 18 01 01 ab`
- **[HIGH-ENTROPY]** `tlsStdModuleRemove`  VA=0xffffffff803d894c  off=0x2d894c
    high-entropy (H=4.50/8 over a key-sized window) — likely key/secret material
    `f4 4f be a9 fd 7b 01 a9 f4 3a 00 d0 88 2a 45 b9 f3 03 00 aa fd 43 00 91 a8 00 00 34 00 3d 00 b0`
- **[HIGH-ENTROPY]** `tlsStdModuleBlockOffset`  VA=0xffffffff803d89cc  off=0x2d89cc
    high-entropy (H=4.44/8 over a key-sized window) — likely key/secret material
    `f4 4f be a9 fd 7b 01 a9 fd 43 00 91 00 03 00 b4 f4 3a 00 d0 88 2a 45 b9 f3 03 00 aa a8 00 00 34`
- **[HIGH-ENTROPY]** `__tlsTaskResetHook`  VA=0xffffffff803d8a78  off=0x2d8a78
    high-entropy (H=4.80/8 over a key-sized window) — likely key/secret material
    `f9 0f 1b f8 f8 5f 01 a9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 08 3d 00 b0 09 11 41 f9 fd 03 01 91`
- **[HIGH-ENTROPY]** `__tlsTaskCreateHook`  VA=0xffffffff803d8bd4  off=0x2d8bd4
    high-entropy (H=5.08/8 over a key-sized window) — likely key/secret material
    `fb 0f 1a f8 fa 67 01 a9 f8 5f 02 a9 f6 57 03 a9 f4 4f 04 a9 fd 7b 05 a9 19 3d 00 b0 28 13 41 f9`
- **[HIGH-ENTROPY]** `qPriBMapKey`  VA=0xffffffff803fde1c  off=0x2fde1c
    high-entropy (H=4.69/8 over a key-sized window) — likely key/secret material
    `00 08 40 f9 c0 03 5f d6 f5 0f 1d f8 f4 4f 01 a9 fd 7b 02 a9 09 08 40 f9 f3 03 00 aa fd 83 00 91`
- **[HIGH-ENTROPY]** `qPriDeltaKey`  VA=0xffffffff803fe19c  off=0x2fe19c
    high-entropy (H=4.53/8 over a key-sized window) — likely key/secret material
    `e8 03 1f aa 80 00 00 b4 00 a4 40 a9 28 01 08 8b c0 ff ff b5 e0 03 08 aa c0 03 5f d6 01 02 00 b4`
- **[HIGH-ENTROPY]** `tcf_generate_ssl_certificate`  VA=0xffffffff80404200  off=0x304200
    high-entropy (H=4.68/8 over a key-sized window) — likely key/secret material
    `00 32 00 f0 e1 28 00 d0 00 e0 3c 91 21 a0 10 91 36 c5 fa 17 fd 7b bf a9 e0 03 1d 32 fd 03 00 91`
- **[HIGH-ENTROPY]** `tcf_get_tls_address`  VA=0xffffffff8047c05c  off=0x37c05c
    high-entropy (H=4.67/8 over a key-sized window) — likely key/secret material
    `fc 6f ba a9 fa 67 01 a9 f8 5f 02 a9 f6 57 03 a9 f4 4f 04 a9 fd 7b 05 a9 fd 43 01 91 ff 03 07 d1`
- **[HIGH-ENTROPY]** `ipcom_route_key_cmp`  VA=0xffffffff8047def0  off=0x37def0
    high-entropy (H=4.94/8 over a key-sized window) — likely key/secret material
    `1f 0c 00 72 40 03 00 54 e8 03 1f 2a 08 71 1d 53 1f 01 00 6b 8a 02 00 54 e9 03 19 32 0a 7d 43 93`
- **[HIGH-ENTROPY]** `_ZStlsISt11char_traitsIcEERSt13basic_ostreamIcT_ES5_PKc`  VA=0xffffffff804b2f10  off=0x3b2f10
    high-entropy (H=4.69/8 over a key-sized window) — likely key/secret material
    `ff 43 01 d1 f7 0b 00 f9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 fd 03 01 91 f4 03 01 aa f3 03 00 aa`
- **[HIGH-ENTROPY]** `_ZNKSt5ctypeIcE9do_narrowEcc`  VA=0xffffffff804b60c8  off=0x3b60c8
    high-entropy (H=4.64/8 over a key-sized window) — likely key/secret material
    `e0 03 01 2a c0 03 5f d6 f3 0f 1e f8 fd 7b 01 a9 fd 43 00 91 e0 03 04 aa f3 03 02 aa 42 00 01 cb`
- **[HIGH-ENTROPY]** `SHA1_version`  VA=0xffffffff80803f70  off=0x703f70
    high-entropy (H=4.40/8 over a key-sized window) — likely key/secret material
    `53 48 41 31 20 70 61 72 74 20 6f 66 20 4f 70 65 6e 53 53 4c 20 31 2e 30 2e 32 73 20 20 32 38 20`
- **[HIGH-ENTROPY]** `SHA256_version`  VA=0xffffffff80803f99  off=0x703f99
    high-entropy (H=4.44/8 over a key-sized window) — likely key/secret material
    `53 48 41 2d 32 35 36 20 70 61 72 74 20 6f 66 20 4f 70 65 6e 53 53 4c 20 31 2e 30 2e 32 73 20 20`
- [string] `ipcrypto`  VA=0xffffffff809016ea  off=0x8016ea
    string: 'ipipsec ipike ipl2tp ipldapc iplite ipnat ippppoe ipradius iprip ipssh ipssl ipsslproxy ipftp ipfirewall ipdhcpd ipdhcpc ipwebs iptftp ipdhc'
    `69 70 69 70 73 65 63 00 69 70 69 6b 65 00 69 70 6c 32 74 70 00 69 70 6c 64 61 70 63 00 69 70 6c`
- [string] `ipssl`  VA=0xffffffff80901737  off=0x801737
    string: 'ipsslproxy ipftp ipfirewall ipdhcpd ipdhcpc ipwebs iptftp ipdhcps ipdhcps6 ipsnmp ipdhcpr ipcom_drv_eth ipppp ipappl ipmlds ipemanate ipfree'
    `69 70 73 73 6c 70 72 6f 78 79 00 69 70 66 74 70 00 69 70 66 69 72 65 77 61 6c 6c 00 69 70 64 68`
- [string] `ipsslproxy`  VA=0xffffffff80901742  off=0x801742
    string: 'ipftp ipfirewall ipdhcpd ipdhcpc ipwebs iptftp ipdhcps ipdhcps6 ipsnmp ipdhcpr ipcom_drv_eth ipppp ipappl ipmlds ipemanate ipfreescale ipmcp'
    `69 70 66 74 70 00 69 70 66 69 72 65 77 61 6c 6c 00 69 70 64 68 63 70 64 00 69 70 64 68 63 70 63`
- [string] `iphwcrypto`  VA=0xffffffff809017fa  off=0x8017fa
    string: 'ipnetsnmp ipquagga ipdhcpc6 ipcci ipdiameter iprohc ipsctp ipifproxy ipcom_key_db ipwps f-57 ipripng ipntp wrnad ipbridge ipforwarder *ILLEG'
    `69 70 6e 65 74 73 6e 6d 70 00 69 70 71 75 61 67 67 61 00 69 70 64 68 63 70 63 36 00 69 70 63 63`
- [string] `ipcom_key_db`  VA=0xffffffff8090184c  off=0x80184c
    string: 'ipwps f-57 ipripng ipntp wrnad ipbridge ipforwarder *ILLEGAL* Emerg Crit Warning Notice Debug2 IPCOM network job Print slab cache informatio'
    `69 70 77 70 73 00 66 2d 35 37 00 69 70 72 69 70 6e 67 00 69 70 6e 74 70 00 77 72 6e 61 64 00 69`
- [string] `auth`  VA=0xffffffff809399cb  off=0x8399cb
    string: 'syslog ipcom_syslogd_init ipcom_syslog_facility_names ipcom_syslog_printf ipcom_syslog_priority_names ipcom_sys_malloc ipcom_sysvar_add_obse'
    `73 79 73 6c 6f 67 00 69 70 63 6f 6d 5f 73 79 73 6c 6f 67 64 5f 69 6e 69 74 00 69 70 63 6f 6d 5f`
- [data] `_ZN10coeMessageC2EjP12coeEncryptorS1_jjPj`  VA=0xffffffff8012b0f4  off=0x2b0f4
    mixed data (H=4.25/8)
    `f9 0f 1b f8 f8 5f 01 a9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 fd 03 01 91 f4 03 06 aa f5 03 05 2a`
- [data] `_ZN10coeMessageC2EPjjP12coeEncryptorS2_jjS0_`  VA=0xffffffff8012b194  off=0x2b194
    mixed data (H=4.26/8)
    `fa 67 bb a9 f8 5f 01 a9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 fd 03 01 91 f4 03 07 aa f5 03 06 2a`
- [data] `_ZN10coeMessage25getEncryptedBufferAddressERjRi`  VA=0xffffffff8012b3a8  off=0x2b3a8
    mixed data (H=3.86/8)
    `00 04 40 f9 40 00 00 b4 94 0a 00 14 e8 03 1f 32 48 00 00 b9 c0 03 5f d6 00 04 40 f9 40 00 00 b4`
- [data] `_ZN10coeMessage7encryptEj`  VA=0xffffffff8012b488  off=0x2b488
    mixed data (H=3.67/8)
    `00 04 40 f9 40 00 00 b4 7d 0a 00 14 e0 03 1f 32 c0 03 5f d6 00 04 40 f9 40 00 00 b4 18 0a 00 14`
- [data] `_ZN10coeMessage7decryptEv`  VA=0xffffffff8012b49c  off=0x2b49c
    mixed data (H=3.67/8)
    `00 04 40 f9 40 00 00 b4 18 0a 00 14 e0 03 1f 32 c0 03 5f d6 00 04 40 f9 40 00 00 b4 ec 0a 00 14`
- [data] `_ZN16GpsKeyActionTypeC2Ev`  VA=0xffffffff8021ff58  off=0x11ff58
    mixed data (H=3.22/8)
    `1f 00 00 f9 1f 08 00 b9 c0 03 5f d6 1f 00 00 f9 1f 08 00 b9 c0 03 5f d6 1f 00 00 f9 1f 08 00 b9`
- [data] `_ZN16GpsKeyActionType7DefaultEv`  VA=0xffffffff8021ff64  off=0x11ff64
    mixed data (H=3.27/8)
    `1f 00 00 f9 1f 08 00 b9 c0 03 5f d6 1f 00 00 f9 1f 08 00 b9 28 00 40 b9 08 00 00 b9 28 04 40 b9`
- [data] `_ZN16GpsKeyActionTypeC2ERKS_`  VA=0xffffffff8021ff70  off=0x11ff70
    mixed data (H=3.07/8)
    `1f 00 00 f9 1f 08 00 b9 28 00 40 b9 08 00 00 b9 28 04 40 b9 08 04 00 b9 28 08 40 b9 08 08 00 b9`
- [data] `_ZN16GpsKeyActionTypeaSERKS_`  VA=0xffffffff8021ff94  off=0x11ff94
    mixed data (H=3.52/8)
    `28 00 40 b9 08 00 00 b9 28 04 40 b9 08 04 00 b9 28 08 40 b9 08 08 00 b9 c0 03 5f d6 08 00 40 b9`
- [data] `_ZN16GpsKeyActionTypeeqERKS_`  VA=0xffffffff8021ffb0  off=0x11ffb0
    mixed data (H=3.73/8)
    `08 00 40 b9 29 00 40 b9 1f 01 09 6b 41 01 00 54 08 04 40 b9 29 04 40 b9 1f 01 09 6b 01 01 00 54`
- [data] `_ZN16GpsKeyActionTypeneERKS_`  VA=0xffffffff8021fff4  off=0x11fff4
    mixed data (H=3.73/8)
    `08 00 40 b9 29 00 40 b9 1f 01 09 6b 41 01 00 54 08 04 40 b9 29 04 40 b9 1f 01 09 6b 01 01 00 54`
- [data] `_ZN16GpsKeyActionType8ValidateEv`  VA=0xffffffff80220038  off=0x120038
    mixed data (H=3.71/8)
    `e0 03 00 32 c0 03 5f d6 1f 7c 00 a9 c0 03 5f d6 1f 7c 00 a9 c0 03 5f d6 1f 7c 00 a9 28 00 40 f9`
- [data] `SHA256_Transform`  VA=0xffffffff8022dc28  off=0x12dc28
    mixed data (H=3.88/8)
    `e2 03 00 32 c5 04 00 14 a8 40 00 d0 03 59 41 f9 e2 03 01 aa e1 03 1f 2a 60 00 1f d6 00 00 00 00`
- [data] `OPENSSL_cleanse`  VA=0xffffffff8022dc30  off=0x12dc30
    mixed data (H=3.70/8)
    `a8 40 00 d0 03 59 41 f9 e2 03 01 aa e1 03 1f 2a 60 00 1f d6 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `secHashSha1TemplateGet`  VA=0xffffffff8028f0dc  off=0x18f0dc
    mixed data (H=3.47/8)
    `e8 44 00 f0 00 09 44 f9 c0 03 5f d6 e8 44 00 f0 00 09 04 f9 c0 03 5f d6 e8 44 00 f0 00 0d 44 f9`
- [data] `secHashSha1TemplateSet`  VA=0xffffffff8028f0e8  off=0x18f0e8
    mixed data (H=4.02/8)
    `e8 44 00 f0 00 09 04 f9 c0 03 5f d6 e8 44 00 f0 00 0d 44 f9 c0 03 5f d6 e8 44 00 f0 00 0d 04 f9`
- [data] `rngFreeBytes`  VA=0xffffffff80300e6c  off=0x200e6c
    mixed data (H=4.24/8)
    `09 28 40 a9 e8 03 00 aa e9 03 29 aa 40 01 09 ab 44 00 00 54 c0 03 5f d6 08 09 40 f9 00 01 00 8b`
- [data] `rngNBytes`  VA=0xffffffff80300e90  off=0x200e90
    mixed data (H=4.30/8)
    `09 28 40 a9 e8 03 00 aa 20 01 0a eb 44 00 00 54 c0 03 5f d6 08 09 40 f9 00 01 00 8b c0 03 5f d6`
- [data] `tlsLoadModuleInfoGet`  VA=0xffffffff8038a614  off=0x28a614
    mixed data (H=4.25/8)
    `fa 67 bb a9 f8 5f 01 a9 f6 57 02 a9 f4 4f 03 a9 fd 7b 04 a9 fd 03 01 91 f4 03 05 aa f3 03 04 aa`
- [data] `taskCredentialsGet`  VA=0xffffffff803a2c60  off=0x2a2c60
    mixed data (H=3.95/8)
    `41 03 00 b4 e8 03 00 aa 00 04 00 b4 09 5d 42 f9 e0 03 1f 2a 29 01 40 79 29 00 00 79 09 5d 42 f9`
- [data] `taskCredentialsSet`  VA=0xffffffff803a2d04  off=0x2a2d04
    mixed data (H=4.03/8)
    `41 03 00 b4 e8 03 00 aa 00 04 00 b4 09 01 40 79 2a 5c 42 f9 e0 03 1f 2a 49 01 00 79 09 05 40 79`
- [data] `randomEntropyInterruptAddInit`  VA=0xffffffff803a7ba8  off=0x2a7ba8
    mixed data (H=4.21/8)
    `c0 00 00 34 48 35 00 d0 00 59 0a b9 08 00 00 90 08 51 2f 91 03 00 00 14 08 00 00 b0 08 b1 02 91`
- [data] `qPriListKey`  VA=0xffffffff803fe3cc  off=0x2fe3cc
    mixed data (H=4.18/8)
    `00 08 40 f9 c0 03 5f d6 01 02 00 b4 48 04 00 71 e9 03 01 aa 4b 01 00 54 0a 00 40 f9 e9 03 01 aa`
- [data] `randomNumGenLibFuncsLocal`  VA=0xffffffff80a51a60  off=0x951a60
    mixed data (H=2.32/8)
    `14 7e 3a 80 ff ff ff ff 1c 7e 3a 80 ff ff ff ff 24 7e 3a 80 ff ff ff ff 2c 7e 3a 80 ff ff ff ff`
- [data] `__pStaticModTlsDesc`  VA=0xffffffff80a51ec0  off=0x951ec0
    mixed data (H=3.59/8)
    `d8 64 b3 80 ff ff ff ff 12 00 00 00 00 00 00 00 98 21 a5 80 ff ff ff ff 6a 1c 8f 80 ff ff ff ff`
- [data] `OPENSSL_armcap_P`  VA=0xffffffff80b2c958  off=0xa2c958
    mixed data (H=2.06/8)
    `3f 00 00 00 01 00 00 00 67 f9 ff ff ff ff ff ff 00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00`
- [data] `secHashSha1Templ`  VA=0xffffffff80b2e810  off=0xa2e810
    mixed data (H=2.56/8)
    `c8 3e 80 80 ff ff ff ff 08 3f 80 80 ff ff ff ff 00 00 00 00 00 00 00 00 00 b0 2b 00 00 80 ff ff`
- [data] `secHashSha256Templ`  VA=0xffffffff80b2e818  off=0xa2e818
    mixed data (H=2.27/8)
    `08 3f 80 80 ff ff ff ff 00 00 00 00 00 00 00 00 00 b0 2b 00 00 80 ff ff 01 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Times`  VA=0xffffffff80b2f6a0  off=0xa2f6a0
    mixed data (H=3.19/8)
    `00 00 00 00 00 00 00 00 54 68 75 20 4a 61 6e 20 20 31 20 30 30 3a 30 30 3a 30 31 20 31 39 37 30`
- [data] `_Tls_setup__Locale`  VA=0xffffffff80b2f6d0  off=0xa2f6d0
    mixed data (H=1.88/8)
    `00 00 00 00 00 00 00 00 80 fa b2 80 ff ff ff ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Randinit`  VA=0xffffffff80b2f740  off=0xa2f740
    mixed data (H=2.25/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 7c d3 11 6b 00 00 00 00 5b 1b 34 24 00 00 00 00`
- [data] `_Tls_setup__Randseed`  VA=0xffffffff80b2f748  off=0xa2f748
    mixed data (H=2.74/8)
    `00 00 00 00 00 00 00 00 7c d3 11 6b 00 00 00 00 5b 1b 34 24 00 00 00 00 23 e1 45 16 00 00 00 00`
- [data] `_Tls_setup__Costate`  VA=0xffffffff80b2f940  off=0xa2f940
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Ctype`  VA=0xffffffff80b2f948  off=0xa2f948
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Mbcurmax`  VA=0xffffffff80b2faf0  off=0xa2faf0
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Mbstate`  VA=0xffffffff80b2fb78  off=0xa2fb78
    mixed data (H=0.93/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Tolotab`  VA=0xffffffff80b30110  off=0xa30110
    mixed data (H=0.54/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00`
- [data] `_Tls_setup__Touptab`  VA=0xffffffff80b30118  off=0xa30118
    mixed data (H=1.00/8)
    `00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 46 00 00 00`
- [data] `_Tls_setup__Wctrans`  VA=0xffffffff80b30258  off=0xa30258
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_Tls_setup__Wctype`  VA=0xffffffff80b30260  off=0xa30260
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_func_randomAddTimeStamp`  VA=0xffffffff80b35ad0  off=0xa35ad0
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_func_randomHwBytes`  VA=0xffffffff80b35ad8  off=0xa35ad8
    mixed data (H=0.87/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsModuleListHead`  VA=0xffffffff80b36498  off=0xa36498
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsLockIsInitialized`  VA=0xffffffff80b36528  off=0xa36528
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `randomNumGenLibFuncs`  VA=0xffffffff80b4fc68  off=0xa4fc68
    mixed data (H=2.10/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 2c 7e 3a 80 ff ff ff ff`
- [data] `_func_tlsStdModuleBlockOffset`  VA=0xffffffff80b5cae8  off=0xa5cae8
    mixed data (H=2.99/8)
    `cc 89 3d 80 ff ff ff ff 14 a6 38 80 ff ff ff ff 5c 87 3d 80 ff ff ff ff 10 81 38 80 ff ff ff ff`
- [data] `_func_tlsLoadModuleInfoGet`  VA=0xffffffff80b5caf0  off=0xa5caf0
    mixed data (H=3.04/8)
    `14 a6 38 80 ff ff ff ff 5c 87 3d 80 ff ff ff ff 10 81 38 80 ff ff ff ff a0 dc 29 00 00 80 ff ff`
- [data] `_func_tlsStdModuleAdd`  VA=0xffffffff80b5caf8  off=0xa5caf8
    mixed data (H=3.13/8)
    `5c 87 3d 80 ff ff ff ff 10 81 38 80 ff ff ff ff a0 dc 29 00 00 80 ff ff 84 81 38 80 ff ff ff ff`
- [data] `tEntropyTaskStk`  VA=0xffffffff80b5ce90  off=0xa5ce90
    mixed data (H=-0.00/8)
    `ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee`
- [data] `tEntropyTaskExcStk`  VA=0xffffffff80b5ee90  off=0xa5ee90
    mixed data (H=-0.00/8)
    `ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee ee`
- [data] `tEntropyTaskTcb`  VA=0xffffffff80b61ea0  off=0xa61ea0
    mixed data (H=1.47/8)
    `00 00 00 00 ff ff ff ff ff ff ff ff 80 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsOffFromTpToS`  VA=0xffffffff80b79210  off=0xa79210
    mixed data (H=0.95/8)
    `10 00 00 00 00 00 00 00 30 00 00 00 00 00 00 00 3f 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsOffFromTpToD`  VA=0xffffffff80b79218  off=0xa79218
    mixed data (H=0.67/8)
    `30 00 00 00 00 00 00 00 3f 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsAreaSize`  VA=0xffffffff80b79220  off=0xa79220
    mixed data (H=0.34/8)
    `3f 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsDkmBlockSize`  VA=0xffffffff80b79228  off=0xa79228
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `__tlsLockSem`  VA=0xffffffff80b79230  off=0xa79230
    mixed data (H=-0.00/8)
    `00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`
- [data] `_func_taskTlsResetHook`  VA=0xffffffff80b7a5a8  off=0xa7a5a8
    mixed data (H=2.27/8)
    `78 8a 3d 80 ff ff ff ff 47 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`

_158 of 160 crypto-named globals held non-zero data; no validated AES keys._
