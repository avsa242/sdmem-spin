{
    --------------------------------------------
    Filename: mem-fs.sd.fat.spin
    Author: Jesse Burt
    Description: FAT32-formatted SDHC/XC driver
    Copyright (c) 2021
    Started Aug 1, 2021
    Updated Aug 1, 2021
    See end of file for terms of use.
    --------------------------------------------
}

CON

' Error codes
    ENOTFOUND   = -2                            ' no such file or directory
    EEOF        = -3                            ' end of file
    EBADSEEK    = -4                            ' bad seek value
    ENOTIMPLM   = $E000_0000                    ' not implemented

' File open modes
    READ        = 0
    WRITE       = 1

VAR

    long _fseek_pos, _fread_sect
    byte _sect_buff[sd#SECTORSIZE]

OBJ

    sd  : "memory.flash.sd.spi"
    fat : "filesystem.block.fat"
    str : "string"

PUB Null{}
' This is not a top-level object

PUB Startx(SD_CS, SD_SCK, SD_MOSI, SD_MISO): status

    status := sd.init(SD_CS, SD_SCK, SD_MOSI, SD_MISO)
    if lookdown(status: 1..8)
        mount{}
        return
    return FALSE

pub getsbp

    return @_sect_buff

PUB Mount{}: status
' Mount SD card
'   Read SD card boot sector and sync filesystem info
    fat.init(@_sect_buff, sd#SECTORSIZE)        ' point FATfs object to sector buffer
    sd.rdblock(@_sect_buff, 0)                  ' read boot sector into sector buffer
    fat.syncpart{}                              ' get sector # of 1st partition

    sd.rdblock(@_sect_buff, fat.partstart{})    ' now read that sector into sector buffer
    fat.syncbpb{}                               ' update all of the FAT fs data from it

PUB FileSize

    return fat.filesize{}

PUB Find(ptr_str): dirent | rds, endofdir, name_tmp[3], ext_tmp[2], name_uc[3], ext_uc[2]
' Find file, by name
'   Returns: directory entry of file (0..n), or ENOUTFOUND (-2) if not found
    dirent := 0
    rds := 0
    endofdir := false
    repeat                                      ' check each rootdir sector
        sd.rdblock(@_sect_buff, fat.rootdirsector{}+rds)
        dirent := 0
        repeat 16                               ' check each file in the sector
            fat.fopen(dirent)                   ' get current file's info
            if fat.direntneverused{}            ' last directory entry
                endofdir := true
                quit
            if fat.fileisdeleted{}              ' ignore deleted files
                next
            str.left(@name_tmp, ptr_str, 8)     ' filename is leftmost 8 chars
            str.right(@ext_tmp, ptr_str, 3)     ' ext. is rightmost 3 charrs
            name_uc := str.upper(@name_tmp)     ' convert to uppercase
            ext_uc := str.upper(@ext_tmp)
            if strcomp(fat.filename{}, name_uc) and {
}           strcomp(fat.filenameext{}, ext_uc)  ' match found for filename; get
                return dirent+(rds * 16)        '   number relative to entr. 0
            dirent++
        rds++                                   ' go to next root dir sector
    until endofdir
    return ENOTFOUND

PUB FOpen(fn_str, mode): status
' Open file for subsequent operations
'   fn_str: pointer to string containing filename (must be space padded)
'   mode: READ (0), or WRITE (1)
'   Returns: 0 if successful, error code otherwise
    status := find(fn_str)                      ' look for file by name
    if status == ENOTFOUND                      ' not found; what is mode?
        if mode == WRITE                        ' WRITE? Create the file
            return ENOTIMPLM                    'xxx not implemented yet
        elseif mode == READ                     ' READ? It really doesn't exist
            return ENOTFOUND
    fat.fopen(status & $0F)                     ' mask is to keep within # root dir entries per rds
    _fseek_pos := 0
    _fread_sect := fat.filefirstsect{}          ' initialize current sector with file's first
    return 0
    ' xxx set r/w flag?

PUB FRead(ptr_dest, nr_bytes) | nr_read
' Read next block of data from file, up to 512 bytes per call
'   Returns: number of bytes read, or EEOF (-3)
    if _fseek_pos < fat.filesize{}            ' before reading, make sure we aren't already at EOF
        nr_read := nr_bytes <# 512 <# fat.filesize{}-_fseek_pos
        sd.rdblock_lsbf(ptr_dest, nr_read, _fread_sect)'XXX partial read here?
        _fseek_pos += nr_read                 ' keep track of how much we've read
        _fread_sect++
        if _fread_sect > fat.clustlastsect{}    ' if last sector of this cluster is reached,
            followchain{}
            if nextcluster{} <> -1              ' advance to next cluster
                _fread_sect := fat.clust2sect(fat.filenextclust{})
            else
                return EEOF
        return nr_read
    else
        return EEOF
'   XXX read file at _fseek_pos into the beginning of the sector buffer
'   XXX then for the remainder of the 512 bytes, read, but starting after the end
'   XXX of the data in there already.

pub getpos

    return _fseek_pos

PUB FSeek(pos) | seek_clust, clust_offs, rel_sect_nr, clust_nr, sect_offs
' Seek to position in currently open file
    if (pos < 0) or (pos => fat.filesize{})     ' catch bad seek positions;
        return EBADSEEK                         '   return error
    longfill(@seek_clust, 0, 5)                 ' clear local vars

    ' initialize cluster number with the file's first cluster number
    clust_nr := fat.filefirstclust{}

    ' determine which cluster (in "n'th" terms) in the chain the seek pos. is
    seek_clust := pos/fat.bytesperclust{}

    ' use remainder to get offset within cluster
    clust_offs := pos//fat.bytesperclust{}

    ' use high bits of offset within cluster to ge
    '   within the cluster
    rel_sect_nr := clust_offs >> 9

    ' follow the cluster chain to determine which actual cluster it is
    repeat seek_clust
        followchain{}
        clust_nr := nextcluster{}

    ' set the absolute sector number and the seek position for subsequent R/W
    _fread_sect := fat.clust2sect(clust_nr)+rel_sect_nr
    _fseek_pos := pos

    return pos

PUB FollowChain{} | fat_sect
' Read FAT to get next cluster number in chain
    fat_sect := fat.fileprevclust{} >> 7
    sd.rdblock(@_sect_buff, fat.fat1start{} + fat_sect)

PUB NextCluster{}: c
    c := 0
    return fat.nextcluster

pub filenextclust

    return fat.filenextclust

pub bytesperclust

    return fat.bytesperclust

pub clust2sect(c): s

    return fat.clust2sect(c)

pub filefirstclust{}

    return fat.filefirstclust

pub filefirstsect{}

    return fat.filefirstsect

pub readsect(ptr, sect)

    sd.rdblock_lsbf(ptr, 512, sect)

