CON

    _clkmode        = xtal1+pll16x
    _xinfreq        = 5_000_000

' --
    CS              = 3
    SCK             = 1
    MOSI            = 2
    MISO            = 0
' --

OBJ

    ser : "com.serial.terminal.ansi"
    time: "time"
    sd  : "memory.flash.sd.spi"
    fat : "filesystem.block.fat"

VAR

    byte _blkbuff[sd#SECTORSIZE]

PUB Main | r

    ser.start(115_200)
    time.msleep(30)
    ser.clear
    ser.strln(string("serial terminal started"))

    sd.startx(CS, SCK, MOSI, MISO)
    fat.init(@_blkbuff)                         ' point FATfs object to sector buffer

    fatinfo{}                                   ' show lots of low-level info about the FAT
    ser.charin{}

    fsinfosector{}

    repeat

PUB C2S | rsc, fn, sf, rde, ss, lsn, ssa, cn, sc

    sd.rdblock(@_blkbuff, 0)
    rsc := fat.reservedsectors
    fn := fat.numberfats
    sf := fat.sectorsperfat
    rde := 0                                    ' xxx what should this be for fat32?
    ss := fat.logicalsectorbytes
    ssa := rsc + fn * sf + ((32 * rde) / ss)
    cn := 2
    sc := fat.sectorspercluster
    lsn := ssa+(cn-2) * sc
    ser.dec(ssa)
    ser.newline
    ser.dec(lsn)
    repeat

PUB FSInfoSector{}

    sd.rdblock(@_blkbuff, $2001)
    ser.clear{}
    ser.position(0, 0)
    ser.hexdump(@_blkbuff, fat.partition1st, 4, sd#SECTORSIZE, 16)
    ser.str(string("FS information sector signature valid mask: "))
    ser.bin(fat.fissigvalidmask{}, 3)
    ser.newline{}

PUB FATInfo{}

    ser.clear{}
    ser.position(0, 0)
    sd.rdblock(@_blkbuff, $0000)
    sd.rdblock(@_blkbuff, fat.partition1st)
    ser.hexdump(@_blkbuff, fat.partition1st, 4, sd#SECTORSIZE, 16)
    ser.printf1(string("Partition 1 start: %x\n"), fat.partition1st{})
    ser.printf1(string("Volume name: '%s'\n"), fat.volumename{})
    ser.printf1(string("Sectors per cluster: %d\n"), fat.sectorspercluster{})
    ser.printf1(string("Bytes per logical sector: %d\n"), fat.logicalsectorbytes{})
    ser.printf1(string("Reserved sectors: %d\n"), fat.reservedsectors{})
    ser.printf1(string("Number of FATs: %d\n"), fat.numberfats{})
    ser.printf1(string("Media type: %x\n"), fat.mediatype{})
    ser.printf1(string("Sectors per track: %d\n"), fat.sectorspertrack{})
    ser.printf1(string("Heads: %d\n"), fat.heads{})
    ser.printf1(string("Hidden sectors: %d\n"), fat.hiddensectors{})

    ser.printf1(string("Sectors per FAT: %d\n"), fat.sectorsperfat{})
    ser.printf1(string("Flags: %x\n"), fat.fatflags{})
    ser.printf2(string("FAT32 ver: %d.%d\n"), fat.fat32version{} >> 8, fat.fat32version{} & $FF)
    ser.printf1(string("Root cluster: %d\n"), fat.rootdircluster{})
    ser.printf1(string("Filesystem info sector: %d\n"), fat.finfosector{})
    ser.printf1(string("Backup boot sector: %d\n"), fat.backupbootsect{})
    ser.printf1(string("Partition logical drive number: %x\n"), fat.logicaldrvnum{})
    ser.printf1(string("Signature 0x29 is valid? %d\n"), fat.sig0x29valid{})
    ser.printf1(string("Partition SN: %x\n"), fat.partsn{})
    ser.printf1(string("FAT name: '%s'\n"), fat.fat32name{})
    ser.printf1(string("MBR sig valid?: %d\n"), fat.sig0xaa55valid{})
    ser.printf1(string("OEM name: '%s'\n"), fat.oemname{})
    ser.printf1(string("Partition sectors: %d\n"), fat.partsectors{})
    ser.printf1(string("FAT mirroring: %d\n"), fat.fatmirroring{})
    ser.printf1(string("Active fat copy: %d\n"), fat.activefat{})
