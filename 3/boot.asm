;*************************************************
;boot.asm       ---     sccui
;                       Email:  2579732583@qq.com
;*************************************************
        org             0x7c00          ;0x0100

;========        constants
SpOfStack              equ     0x7c00   ;0x0100

BaseOfLoader            equ    0x1000   ;0x0000
OffsetOfLoader          equ    0x0000   ;0x0200  

SectorsOfRootDir        equ     14
SectorNoOfRDStart       equ     19
SectorNoOfFAT1Start     equ     1

BytesPerSector          equ     512                  

start:
        jmp     short   Label_Start
        nop
        BS_OEMName      db      'MINEboot'
        BPB_BytesPerSec dw      512
        BPB_SecPerClus  db      1
        BPB_RsvdSecCnt  dw      1
        BPB_NumFATs     db      2
        BPB_RootEntCnt  dw      224
        BPB_TotSec16    dw      2880
        BPB_Media       db      0xf0
        BPB_FATSz16     dw      9
        BPB_SecPerTrk   dw      18
        BPB_NumHeads    dw      2
        BPB_HiddSec     dd      0
        BPB_TotSec32    dd      0
        BS_DrvNum       db      0
        BS_Reserved1    db      0
        BS_BootSig      db      0x29
        BS_VolID        dd      0
        BS_VolLab       db      'boot loader'
        BS_FileSysType  db      'FAT12   '

Label_Start:

        mov     ax,     cs
        mov     ds,     ax
        mov     es,     ax
        mov     ss,     ax
        mov     sp,     SpOfStack              

;=======        clear screen

        mov     ax,     0600h
        mov     bx,     0700h
        mov     cx,     0
        mov     dx,     0184fh
        int     10h

;=======	set focus

        mov     ax,     0200h
        mov     bx,     0000h
        mov     dx,     0000h
        int     10h

;=======        display on screen : Start Booting

        mov     ax,     1301h
        mov     bx,     000fh
        mov     dx,     0000h
        mov     cx,     10
        push    ax
        mov     ax,     ds
        mov     es,     ax
        pop     ax
        mov     bp,     StartBootMessage
        int     10h

;=======        reset floppy-a

        xor     ah,     ah
        xor     dl,     dl
        int     13h

;=======        search loader.bin
        ;I_InRDZone_SectorNo
Search_InRDZone:
        cmp     word [I_InRDZone_SectorNo],      33
        jz      NotFound_InRDZone
        
        mov     ax,     cs                      ;0x0000
        mov     es,     ax
        mov     bx,     start + 0x0400  
        mov     ax,     [I_InRDZone_SectorNo]
        mov     cx,     1
        call    ReadInSectors
        
;=======        search in one sector
		;I_InOneSector
        mov     si,     LoaderFileName 
        mov     di,     start + 0x0400  
        cld     
Search_InOneSector:
        cmp     word [I_InOneSector],   0
        jz      NoFound_InCurSector
        
;=======        search  int one entry
        ;I_InRDEntry
Search_InRDEntry:
        cmp     word [I_InRDEntry],     0
        jz      Label_FileFound
        
        lodsb    
        cmp     al,     byte [es:di]
        jz      Go_NextLetter
        jmp     NoFound_InCurEntry
             
Go_NextLetter:
        inc     di
        
        dec     word [I_InRDEntry]
        jmp     Search_InRDEntry

;=======        no found in cur entry
NoFound_InCurEntry:
        and     di,     0xffe0 
        add     di,     0x0020
        mov     si,     LoaderFileName
        
        dec     word [I_InOneSector]
        jmp     Search_InOneSector       
        
;=======        no found in cur sector
NoFound_InCurSector:
        inc     word    [I_InRDZone_SectorNo]
        jmp     Search_InRDZone
                     
;========       no found in entire root dir zone
        
NotFound_InRDZone:
        
        mov     ax,     1301h
        mov     bx,     008ch
        mov     dx,     0100h
        mov     cx,     21
        push    ax
        mov     ax,     ds
        mov     es,     ax
        pop     ax
        mov     bp,     NoLoaderMessage
        int     10h
        
        jmp $
        
;========       LoaderFileName-LOADER BIN be found in RD
Label_FileFound:     
        

        and     di,     0ffe0h
        add     di,     01ah
        mov     cx,     word    [es:di]
        push    cx                      ;cx(Cluster)--->Label_LoadingFile,ax
        add     cx,     19+14-2
        mov     ax,     BaseOfLoader
        mov     es,     ax
        mov     bx,     OffsetOfLoader  ;es:bx destination addr of loader
        mov     ax,     cx              ;ax=LBA OF Loader.bin in data zone        
;========       Loading loader.BIN
Label_LoadingFile:
        push    ax
        push    bx
        ;=======        show '.'
        mov     ah,     0eh
        mov     al,     '.'
        mov     bl,     0fh
        int     10h
        
        pop     bx
        pop     ax
        mov     cl,     1
        call    ReadInSectors
        
        pop     ax              ;cx(Cluster)--->Label_LoadingFile,ax
        call    Get_NextFATEntry
        cmp     ax,     0fffh
        jz      Label_FileLoaded
        push    ax
        add     ax,     19+14-2
        add     bx,     [BPB_BytesPerSec]
        jmp     Label_LoadingFile
        
Label_FileLoaded:
        jmp     BaseOfLoader:OffsetOfLoader
        
        ;jmp     $        
;******************************************************
;********* Sub  Functions Begin ***********************
;******************************************************
;Function:   Read one or few sectors from floppy a to es:bx
;Parameters: AX=LBA,CL=count,ES:BX=Addr of destination
;Return: -
ReadInSectors:
        push    bp
        mov     bp,     sp
        
        sub     sp,    2
        mov     byte [bp-2],    cl
        push    bx
        mov     bl,     [BPB_SecPerTrk]
        div     bl
        inc     ah              
        mov     cl,     ah      ;cl--sector number
        mov     dh,     al      
        and     dh,     1       ;dh--head number
        shr     al,     1       
        mov     ch,     al      ;ch--track number
        pop     bx
        mov     dl,     [BS_DrvNum]     ;dl--floppy a
Label_GoOnReading:
        mov     ah,     2       
        mov     al,     byte [bp-2]
        int     13h
        jc      Label_GoOnReading
        add     sp,     2
        
        pop     bp
        ret

;Function:Get the next FAT Entry 
;Parameter:(ax)=current cluster number
;Return:(ax)=next cluster number
Get_NextFATEntry:
        push    es
        push    bx
        
        push    ax
        mov     ax,     cs
        mov     es,     ax
        pop     ax
        mov     byte [Odd],     0
        mov     bx,     3
        mul     bx
        mov     bx,     2
        div     bx
        
        mov     byte [Odd],     dl
        
        xor     dx,     dx
        mov     bx,     [BPB_BytesPerSec]
        div     bx
        push    dx              ;dx=offset in sector
        mov     bx,     start+0x0400
        add     ax,     SectorNoOfFAT1Start      ;ax=LBA OF cur cluster
        mov     cl,     2
        call    ReadInSectors
        
        pop     dx              ;dx=offset in sector
        add     bx,             dx
        mov     ax,     [es:bx]
        cmp     byte [Odd],     0
        jz      Label_Even
        ;====   Odd
        shr     ax,     4
        jmp     sret
        
Label_Even:
        and     ax,     0fffh
        jmp     sret
sret:        
        pop     bx
        pop     es
        ret                 
        
        
;******************************************************
;********* Sub  Functions End *************************
;******************************************************


;=======        normal variables
StartBootMessage        db      "Start Boot"
LoaderFileName          dw      "LOADER  BIN"
Odd                     db      0
NoLoaderMessage         db      "Error:No LOADER Found"
;=========      Index variables
I_InRDZone_SectorNo     dw      SectorNoOfRDStart
I_InOneSector           dw      16
I_InRDEntry             dw      11
        
;========       fill zero until whole Sector 
        times   510-($ - $$)    db      0
        dw      0xaa55
