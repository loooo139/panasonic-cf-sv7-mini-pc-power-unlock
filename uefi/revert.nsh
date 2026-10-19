@echo -off
echo ============================================
echo  CF-SV7 DPTF revert to stock (Setup(1))
echo ============================================
\EFI\tools\setup_var.efi -r Setup(1):0x551=1 Setup(1):0x565=0 Setup(1):0x566=0 Setup(1):0x603=0 Setup(1):0x604=1
echo.
echo Write failed. Rebooting...
stall 3000000
reset
