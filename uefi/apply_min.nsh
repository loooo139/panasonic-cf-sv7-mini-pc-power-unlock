@echo -off
echo ============================================
echo  CF-SV7 minimal DPTF unlock (Setup(1))
echo  MSR lock OFF, cTDP Up, TDP lock OFF,
echo  EC Turbo ON, 90 W brick
echo ============================================
\EFI\tools\setup_var.efi -r Setup(1):0x551=0 Setup(1):0x565=2 Setup(1):0x566=0 Setup(1):0x603=1 Setup(1):0x604=1
echo.
echo Write failed. Rebooting...
stall 3000000
reset
