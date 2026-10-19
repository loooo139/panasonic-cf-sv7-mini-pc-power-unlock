@echo -off
echo ============================================
echo  CF-SV7 full DPTF unlock (Setup(1))
echo  Adds PL1/PL2 overrides to the minimal set.
echo  Not all offsets work on every firmware.
echo ============================================
\EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1 Setup(1):0x53C=1 Setup(1):0x552=1 Setup(1):0x553(4)=20000 Setup(1):0x557=28 Setup(1):0x558=1 Setup(1):0x559(4)=30000
echo.
echo Write failed. Rebooting...
stall 3000000
reset
