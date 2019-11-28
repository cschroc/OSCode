	org			10000h	;0x0200
	jmp			Label_Start
	%include		"fat12.inc"
	
;=======	Constants
BaseOfKernelFile	equ	0x00
OffsetOfKernelFile	equ	0x100000

BaseTmpOfKernelFile	equ	0x00
OffsetTmpOfKernelFile	equ	0x7e00

MemoryStructBufferAddr	equ	0x7e00
	
[SECTION gdt]
LABEL_GDT:		dd	0x00000000,0x00000000
LABEL_DESC_CODE32:	dd	0x0000ffff,0x00cf9a00
LABEL_DESC_DATA32:	dd	0x0000ffff,0x00cf9200

GdtLen			equ	$-LABEL_GDT
GdtPtr			dw	GdtLen - 1
			dd	LABEL_GDT
SelectorCode32		equ	LABEL_DESC_CODE32-LABEL_GDT
SelectorData32		equ	LABEL_DESC_DATA32-LABEL_GDT

[SECTION gdt64]
LABEL_GDT64:		dq	0x0000000000000000			
LABEL_DESC_CODE64:	dq	0x0020980000000000
LABEL_DESC_DATA64:	dq	0x0000920000000000

GdtLen64		equ	$-LABEL_GDT64
GdtPtr64		dw	GdtLen64 - 1
			dd	LABEL_GDT64				 
				
[SECTION .s16]
[BITS		 16]
Label_Start:
				
	mov	ax,	cs
	mov	ds,	ax
	mov	es,	ax	;mov	ax,	0x00
	mov	ss,	ax
	mov	sp,	0x7c00
				
;========	display	on screen:Start	Loader ...
	mov	ax,	1301h	 
	mov	bx,	000fh
	mov	dx,	0200h
	mov	cx,	12
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartLoaderMessage
	int	10h
				
;=======	open	address	A20
	push	ax
	in	al,	92h
	or	al,	00000010b
	out	92h,	al
	pop	ax

	cli
	db	0x66
	lgdt	[GdtPtr]	;(index)24-1--->GDTR
				
	mov	eax,	cr0
	or	eax,	1
	mov	cr0,	eax
				
	mov	ax,	SelectorData32	
	mov	fs,	ax	;Data32-index	16--->FS
				
	mov	eax,	cr0
	and	al,	11111110b
	mov	cr0,	eax
	sti								 
	
;=======	reset floppy
	xor	ah,	ah
	xor	dl,	dl
	int 	13h


;=======        search loader.bin
	;; I_InRDZone_SectorNo	equ	19 
Search_InRDZone:
        cmp     word [I_InRDZone_SectorNo],      33
        jz      NotFound_InRDZone
        
        mov     ax,     00h                      ;0x0000
        mov     es,     ax
        mov     bx,     8000h  
        mov     ax,     [I_InRDZone_SectorNo]
        mov     cx,     1
        call    ReadInSectors
        
;=======        search in one sector
	;; I_InOneSector	equ	0
        mov     si,     KernelFileName 
        mov     di,     8000h  
        cld     
Search_InOneSector:
        cmp     word [I_InOneSector],   0
        jz      NoFound_InCurSector
        
;=======        search  int one entry
        ;;I_InRDEntry		equ	11
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
        mov     si,     KernelFileName
	;;restore I_InRDEntry - 11
	mov 	word [I_InRDEntry],	11
        
        dec     word [I_InOneSector]
        jmp     Search_InOneSector       
        
;=======        no found in cur sector
NoFound_InCurSector:
	;;restore I_InOneSector
	mov 	word [I_InOneSector],	16
	
	inc     word    [I_InRDZone_SectorNo]
        jmp     Search_InRDZone
                     
;========       no found in entire root dir zone
        
NotFound_InRDZone:
        
        mov     ax,     1301h
        mov     bx,     008ch
        mov     dx,     0300h
        mov     cx,     21
        push    ax
        mov     ax,     ds
        mov     es,     ax
        pop     ax
        mov     bp,     NoKernelMessage
        int     10h
        
        jmp $
        
;========       FileName-KERNEL BIN be found in RD
Label_FileFound:     

        and     di,     0ffe0h
        add     di,     01ah
        mov     cx,     word    [es:di]
        push    cx             	;cx(Cluster)--->Label_LoadingFile,ax
        add     cx,     19+14-2
        mov     eax,	BaseTmpOfKernelFile
        mov     es,     eax
        mov     bx,     OffsetTmpOfKernelFile
        mov     ax,     cx

;========       Loading kernel.bin
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
;;; 	copy file by byte
	push	cx
	push	eax
	push 	fs
	push	edi
	push	ds
	push 	esi

	mov	cx,	200h
	mov	ax,	BaseOfKernelFile
	mov	fs,	ax
	mov	edi,	dword	[OffsetOfKernelFileCount]

	mov	ax,	BaseTmpOfKernelFile
	mov	ds,	ax
	mov	esi,	OffsetTmpOfKernelFile

Label_Mov_Kernel:
	mov	al,	byte [ds:esi]
	mov	byte [fs:edi],	al
	inc	esi
	inc 	edi
	loop	Label_Mov_Kernel

	mov	eax,	0x1000
	mov	ds,	eax

	mov	dword	[OffsetOfKernelFileCount], edi

	pop	esi
	pop	ds
	pop	edi
	pop	fs
	pop	eax
	pop	cx
;;; ====	
	call    Get_NextFATEntry
        cmp     ax,     0fffh
        jz      Label_FileLoaded
        push    ax
        add     ax,     19+14-2
	;;add     bx,     [BPB_BytesPerSec] 
        jmp     Label_LoadingFile
	
Label_FileLoaded:
	mov	ax,	0B800h
	mov	gs,	ax
	mov	ah,	0Fh	;black backgroud, white frontgroud
	mov	al,	'G'
	mov	[gs:((80*0+39)*2)],	ax ;0-l 39-c

	jmp     $		
;;; ====	close floppy a
KillMotor:			
	push	dx
	mov	dx,	03F2h
	mov	al,	0
	out	dx,	al
	pop	dx
	
	
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
        mov     bx,     8000h
        add     ax,     SectorNumOfFAT1Start      ;ax=LBA OF cur cluster
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
;********* Sub  Functions End   ***********************
;******************************************************
;;; ====	TMP Variables
OffsetOfKernelFileCount	dd	OffsetOfKernelFile
Odd			db	0
;;;========	display message
StartLoaderMessage:	db	"Start Loader"			 
NoKernelMessage:	db	"No Kernel found"
KernelFileName:		db	"KERNEL  BIN",0

;;; =====	Index variables
I_InRDZone_SectorNo	dw	19
I_InOneSector		dw	16
I_InRDEntry		dw	11
