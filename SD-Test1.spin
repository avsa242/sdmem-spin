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

VAR

    long _CS
    byte _blkbuff[512]

PUB Main | r

    ser.start(115_200)
    time.msleep(30)
    ser.clear
    ser.strln(string("serial terminal started"))

    sd.init(CS, SCK, MOSI, MISO)
    ser.strln(string("reading block..."))
    sd.rdblock(@_blkbuff, $6000)
    ser.hexdump(@_blkbuff, 0, 4, 512, 16)
    repeat

