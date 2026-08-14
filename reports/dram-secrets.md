# DRAM secrets scan — 33554432 bytes (base 0x00100000)

**66 findings** — 5 CRIT, 61 MED

Heuristic — verify each before acting. CRIT/HIGH first.


## vxworks-bootline  (5)
- **[CRIT]** `0x008f05a1`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.2 e=192.168.1.6:ffffff00 g=192.168.1.1 u=target pw=vxTarget`
- **[CRIT]** `0x008f05e9`  boot user/password: `u=target  pw=vxTarget`
- **[CRIT]** `0x00a2dc40`  VxWorks boot line: `gem(0,0)host:vxWorks h=192.168.1.20 e=192.168.1.10:ffffff00 u=ultraNP pw=ultraNP f=0x0`
- **[CRIT]** `0x00a2dc7c`  boot user/password: `u=ultraNP  pw=ultraNP`
- **[CRIT]** `0x00b8253c`  boot user/password: `u=ultraNP  pw=ultraNP`

## cred-keyword  (5)
- **[MED]** `0x0091f267`  keyword: `iam       "user"[,"passwd"]    Set user name and passwd, possibly in`
- **[MED]** `0x0091f8fe`  keyword: `iam          "usr"[,"passwd"]      - specify the user name by which you`
- **[MED]** `0x0091f989`  keyword: `(and optional password)`
- **[MED]** `0x00a51dc8`  keyword: `ftp password (pw)`
- **[MED]** `0x00ba6688`  keyword: `ftp password (pw)`

## key-candidate  (56)
- **[MED]** `0x0014ef30`  isolated high-entropy region 32B (H=4.75): `299d2f918a0000102b6968384a090b8b40011fd6280680521e000014e8071c32`
- **[MED]** `0x00806a10`  isolated high-entropy region 32B (H=4.85): `4a4236b8fe788012e47e24e25589004067229bbacf649fca3834fddfd8fefe3f`
- **[MED]** `0x00807170`  isolated high-entropy region 32B (H=5.00): `641ad1fc9cd76ca11432eadb2efdfe3f7f6abc74931804560e2db29def430240`
- **[MED]** `0x008073c0`  isolated high-entropy region 48B (H=4.81): `b755ac0678b55fb3c39d658361180240abad347466259a241f8beaab2cb30040…`
- **[MED]** `0x00807b10`  isolated high-entropy region 48B (H=4.94): `545dcc80f13d0d77a757ed6fc6dc0240b28bfc2c982c4745c1f3c8c09b7dfe3f…`
- **[MED]** `0x00807f90`  isolated high-entropy region 112B (H=4.79): `0e2db29defa70fc025068195438b0fc0e62f7c5471a40fc0dd6eeda92b8fbe3c…`
- **[MED]** `0x00808ba0`  isolated high-entropy region 512B (H=4.94): `e258b4650b1fd8cec89758b2168001c043aa42906dd070985fb6d4a93c1a903f…`
- **[MED]** `0x00808e20`  isolated high-entropy region 32B (H=4.88): `580f325ad2cabc0c90bda110b45f00c0fb5219cc7abde169607d4bffb4408f3f`
- **[MED]** `0x00808ef0`  isolated high-entropy region 64B (H=5.00): `79e9263108ac1c5a643bdf4f8d4700c003098a1f63ee5a423ee8d9acfa2c00c0…`
- **[MED]** `0x0081b0c0`  isolated high-entropy region 32B (H=4.81): `7bd1ba39d6d9f83ad75eeeba1ebca2bb6f5c5d3ded5e423f42bf20403338603e`
- **[MED]** `0x0081cfa0`  isolated high-entropy region 32B (H=4.88): `0080e03779c34143176e05b5b5b89346f5f93fe9034f384d321d30f94877825a`
- **[MED]** `0x0081d150`  isolated high-entropy region 32B (H=4.73): `3435363738396162636465664142434445460064696f75785870000a00080a10`
- **[MED]** `0x0081dca0`  isolated high-entropy region 32B (H=5.00): `494a4b4c4d4e4f505152535455565758595a005e6162666e7274763031323334`
- **[MED]** `0x008211f0`  isolated high-entropy region 32B (H=4.88): `23dbf97e6abc74931804560e2df2fe3f022b8716d9cef753e3a59bc420f0fe3f`
- **[MED]** `0x008d2660`  isolated high-entropy region 32B (H=4.94): `cc5e6cb27da6a1191d27ef13cadd0240decf8f6667dcbbe72a9439be3f2f913f`
- **[MED]** `0x008d27a0`  isolated high-entropy region 32B (H=4.73): `0acaca25c5cd4a17f1d55f4ae5b70340e31c240a1e9ba44ac7e8c853873c923f`
- **[MED]** `0x008d58e0`  isolated high-entropy region 32B (H=4.88): `3b93325fc68b83fcbeb2e676840104406f290a87e79881b91e60e2326c6c903f`
- **[MED]** `0x008ddbf0`  isolated high-entropy region 32B (H=4.81): `c5df1dd024d9bd5ff176ac6bc4cc02409c20342d131b760e4aa239bb1dc5903f`
- **[MED]** `0x008ddce0`  isolated high-entropy region 32B (H=4.81): `92c4b55769d04ecb95794193497e03403f87cf1df0b66cc4dc811026dc0a8c3f`
- **[MED]** `0x008dddd0`  isolated high-entropy region 32B (H=4.75): `b0aef8eefaa0703eb6b49a96d60a04404e702d0e240a878725a7ae1b4171923f`
- **[MED]** `0x008e9ea0`  isolated high-entropy region 32B (H=4.94): `020201030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f`
- **[MED]** `0x008ece10`  isolated high-entropy region 32B (H=5.00): `636465666768696a6b6c6d6e6f707172737475767778797a3031323334353637`
- **[MED]** `0x00906e80`  isolated high-entropy region 32B (H=4.75): `1f7fd03b19a2a73dde40e63e00000000fdd7fe14a9e31ad1b6290475dd20ff3f`
- **[MED]** `0x00907d80`  isolated high-entropy region 32B (H=4.73): `bfbf90b99ebfcc3d1354083cf389633741821a401502993e11aecc3ec0aa2a3f`
- **[MED]** `0x00908f00`  isolated high-entropy region 32B (H=5.00): `95007f2a9892352f411405a4c088257587434702c75bbc3f9da59109ba4dd80a`
- **[MED]** `0x0090aa60`  isolated high-entropy region 32B (H=4.79): `b90117c58c896984d14244b51f92ff3f48e17a14ae47d13fa4703d0ad7a3e03f`
- **[MED]** `0x0090ac00`  isolated high-entropy region 192B (H=4.94): `44ad96a502027f7ca3498f61fbc6e63f4cde38040c93c9c35f4b2b95727dfdbf…`
- **[MED]** `0x0090aeb0`  isolated high-entropy region 48B (H=4.88): `1ad9fe14a9e31ad1b6290475dd20fd3f60eaa3af4ef8532a889cdc06f345fb3f…`
- **[MED]** `0x0090bba0`  isolated high-entropy region 32B (H=5.00): `069e6ecd0f8b9481a75bf3c39f6602c0b083312b8d1e5141b621a078da2a0140`
- **[MED]** `0x0090c290`  isolated high-entropy region 32B (H=4.94): `68eaa3af4ef8532a889cdc06f345fe3f58c7a2fc83208778322bc5b681bb8e3f`
- **[MED]** `0x009f0bc0`  isolated high-entropy region 32B (H=4.73): `1c5c72ff8001000000600c1d109e029d0493069408950a960c970e981099129a`
- **[MED]** `0x009f2f90`  isolated high-entropy region 32B (H=4.73): `ff600c1d109e029d0493069408950a960c970e981099129a149b169c18000000`
- **[MED]** `0x009f3e40`  isolated high-entropy region 32B (H=4.73): `3807000000600c1d109e029d0493069408950a960c970e981099129a149b169c`
- **[MED]** `0x009f4310`  isolated high-entropy region 32B (H=4.73): `6c05000000640c1d109e029d0493069408950a960c970e981099129a149b169c`
- **[MED]** `0x009f4b70`  isolated high-entropy region 32B (H=4.73): `ff600c1d109e029d0493069408950a960c970e981099129a149b169c18000000`
- **[MED]** `0x009f4cd0`  isolated high-entropy region 32B (H=4.73): `ff600c1d109e029d0493069408950a960c970e981099129a149b169c18000000`
- **[MED]** `0x009f5e80`  isolated high-entropy region 112B (H=4.88): `109e029d0493069408950a960c970e981099129a149b169c1805481c18000000…`
- **[MED]** `0x009f5f80`  isolated high-entropy region 32B (H=4.73): `109e029d0493069408950a960c970e981099129a149b169c1805481c18000000`
- **[MED]** `0x009f61e0`  isolated high-entropy region 32B (H=4.73): `ff600c1d109e029d0493069408950a960c970e981099129a149b169c18000000`
- **[MED]** `0x009f6480`  isolated high-entropy region 112B (H=4.73): `109e029d0493069408950a960c970e981099129a149b169c1805481c18000000…`
  …and 16 more (heuristic noise — top 40 by rank shown)
