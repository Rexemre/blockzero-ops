# Official Block Zero MAINNET chain identity.
# Update $OfficialGenesis after mining the mainnet genesis - see blockzero-docs/mainnet-launch.md

$OfficialGenesis = "44c1a8c852b3eda21966e1ddb6b0807e22488dffe8a270bf24bf1fa2d66c13bd"

$OfficialGenesisMessage = "The Times 06/Jun/2026 Block Zero - a second chance at Genesis"
$OfficialGenesisTime = 1780725966   # 2026-06-06T06:06:06Z (launch moment)

# Mainnet P2P seed and ports.
# RPC is local-only. Port 8332 (Bitcoin's standard mainnet RPC port) avoids the
# Hyper-V/WSL reserved-port range that blocks binding 8211 on some Windows hosts
# (WSAEACCES / error 10013). The public seed P2P port stays 8210.
$SeedNode = "217.160.46.61:8210"
$RpcPort  = 8332
$P2PPort  = 8210

# Block 1 is mined fresh after launch; only the genesis hash is fixed.
