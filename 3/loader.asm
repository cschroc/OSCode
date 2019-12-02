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

	
[SECTION .s16]
[BITS	16]
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

	;; jmp     $		
;;; ====	close floppy a
KillMotor:			
	push	dx
	mov	dx,	03F2h
	mov	al,	0
	out	dx,	al
	pop	dx


;;; ====	MEMORY_ADDR_STRUCT ---> 0x7e00
	mov 	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0400h	;row 4
	mov 	cx,	24
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartGetMemStructMessage
	int 	10h

	mov	ebx,	0
	mov	ax,	0x00
	mov 	es,	ax
	mov	di,	MemoryStructBufferAddr
Label_Get_Mem_Struct:
	mov	eax,	0x0E820
	mov	ecx,	20
	mov	edx,	0x534D4150
	int 	15h
	jc	Label_Get_Mem_Fail
	add	di,	20
	
	cmp 	ebx,	0
	jne	Label_Get_Mem_Struct ;fail--again
	jmp	Label_Get_Mem_OK
	
Label_Get_Mem_Fail:
	mov	ax,	1301h
	mov	bx,	008Ch
	mov	dx,	0500h	;row 5
	mov	cx,	23
	push 	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetMemStructErrMessage
	int	10h
	jmp	$
		
Label_Get_Mem_OK:
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0600h	;row 6
	mov	cx,	29
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetMemStructOKMessage
	int 	10h
;;; ====	MEMORY_ADDR_STRUCT--END
	
;;; ====	VBEInfoBlock ---> 0x8000
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0800h	;row 8
	mov	cx,	23
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop 	ax
	mov	bp,	StartGetSVGAVBEInfoMessage
	int	10h


	mov	ax,	0x00
	mov	es,	ax
	mov	di,	0x8000
	mov	ax,	4F00h
	int 	10h

	cmp	ax,	004Fh
	jz	.OK
	jmp	.Fail
;;; ====	Fail
.Fail:
	mov	ax,	1301h
	mov	bx,	008Ch
	mov	dx,	0900h	;row 9
	mov	cx,	23
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAVBEInfoErrMessage
	int 	10h

	jmp	$

;;; ====	OK
.OK:
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0A00h	;row 12
	mov	cx,	29
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAVBEInfoOKMessage
	int	10h
;;; ===		VBEinfoblock--->END
	
;;; === 	SVGA Mode Info	--->	0x8200 
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0C00h
	mov	cx,	24
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	StartGetSVGAModeInfoMessage
	int	10h
	

	mov	ax,	0X00
	mov	es,	ax
	mov	si,	0x800e
	mov	esi,	dword [es:si] 	;VBEinfoblock.[0e-11]-->esi
	mov	edi,	0x8200
Label_SVGA_Mode_Info_Get:
	mov	cx,	word	[es:esi] ;mode info-->cx
;;; ====	display cx(mode info) in hex mode
	push	ax
	mov	ax,	00h
	mov	al,	ch
	call	Label_Display_InHex

	mov	ax,	00h
	mov	al,	cl
	call	Label_Display_InHex
	pop	ax
	
;;; ====	cx---mode info
	cmp	cx,	0FFFFh	
	jz	Label_SVGA_Mode_Info_Finish

	mov	ax,	4F01h	 
	int 	10h

	cmp	ax,	004Fh
	jnz	Label_SVGA_Mode_Info_Fail

	add	esi,	2
	add	edi,	0x100
	jmp	Label_SVGA_Mode_Info_Get

Label_SVGA_Mode_Info_Fail:
	jmp	$
	
Label_SVGA_Mode_Info_Finish:
	mov	ax,	1301h
	mov	bx,	000Fh
	mov	dx,	0E00h	;row 14
	mov	cx,	30
	push	ax
	mov	ax,	ds
	mov	es,	ax
	pop	ax
	mov	bp,	GetSVGAModeInfoOKMessage
	int	10h
;;; ====	set the SVGA mode
	mov	ax,	4F02h
	mov	bx,	4180h	;=====mode:0x180 or 0x143
	int 	10h

	cmp	ax,	004Fh
	jnz	Label_Set_SVGA_Mode_Fail
	jmp	Label_Set_SVGA_Mode_OK	
Label_Set_SVGA_Mode_Fail:	
	jmp	$

Label_Set_SVGA_Mode_OK:
;;; ====	init	IDT GDT goto protect mode
	cli			;close interrupt
	db	0x66
	lgdt	[GdtPtr]

	;; if confirm will not generate interrupt, no need lidt
;;; 	db	0x66
;;; 	lidt	[IDT_POINTER]

	mov	eax,	cr0	;protect mode
	or	eax,	1
	mov	cr0,	eax

	jmp	dword	SelectorCode32:GO_TO_TMP_Protect 

[SECTION .s32]
[BITS 32]
GO_TO_TMP_Protect:
	jmp	$
	
;******************************************************
;********* Sub  Functions Begin ***********************
;******************************************************
;Function:   Read one or few sectors from floppy a to es:bx
;Parameters: AX=LBA,CL=count,ES:BX=Addr of destination
;Return: -
	
[SECTION .s16lib]
[BITS 16]
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
;;; Function: display one number in hex
;;; Parameters:(AL)=0xMN
;;; Return:
Label_Display_InHex:
	push	ecx
	push 	edx
	push	edi
	
	mov	edi,	[DisplayPosition]
	mov	ah,	0Fh
	mov	dl,	al
	shr	al,	4

	mov	ecx,	2
.begin:
	and	al,	0Fh
	cmp	al,	9
	ja	.1		;M/N > 9   -->.1
	jmp	.2		;M/N <=9   -->.2
.1:
	sub	al,	0Ah
	add	al,	'A'
	jmp	.3
.2:
	add	al,	'0'	
.3:	
	mov	[gs:edi],	ax

	add	edi,	2
	mov	al,	dl
	loop	.begin

	mov	[DisplayPosition],	edi
	pop	edi
	pop	edx
	pop	ecx
	
	ret
;;; Function:check machine about supporting long mode or not
;;; parameters:null
;;; return: eax
support_long_mode:
	mov	eax,	0x80000000
	cpuid
	cmp	eax,	0x80000001
	setnb	al			;if( !< or >= ) al=1
	jb	support_long_mode_done 	;if( < ) jmp
	mov	eax,	0x80000001
	cpuid
	bt 	edx,	29		;the 29th bit of edx-->cf
	setc	al			;if(cf==1) al=1
	

support_long_mode_done:	
	movzx	eax,	al	;al-->eax
	ret
	
;******************************************************
;********* Sub  Functions End   ***********************
;******************************************************
;;; ====	TMP IDT
IDT:
	times	0x50	dq	0
IDT_END:

IDT_POINTER:
	dw 	IDT_END - IDT - 1
	dd	IDT 

;;; ====	TMP Variables
OffsetOfKernelFileCount	dd	OffsetOfKernelFile
Odd			db	0
DisplayPosition		dd	0
	
;;;========	display message
StartLoaderMessage:	db	"Start Loader"			 
NoKernelMessage:	db	"No Kernel found"
KernelFileName:		db	"KERNEL  BIN",0
StartGetMemStructMessage:	db	"Start Get Memory Struct."
GetMemStructErrMessage:	db	"Get Memory Struct ERROR"
GetMemStructOKMessage:	db	"Get Memory Struct SUCCESSFUL!"

StartGetSVGAVBEInfoMessage:	db	"Start Get SVGA VBE Info"
GetSVGAVBEInfoErrMessage:	db	"Get SVGA VBE Info ERROR"
GetSVGAVBEInfoOKMessage:	db	"Get SVGA VBE Info SUCCESSFUL"

StartGetSVGAModeInfoMessage:	db	"Start Get SVGA Mode Info"
GetSVGAModeInfoErrMessage:	db	"Get SVGA Mode Info ERROR"
GetSVGAModeInfoOKMessage:	db	"Get SVGA Mode Info SUCCESSFUL"

SetSVGAModeInfoOKMessage:	db	"Set SVGA Mode Info SUCCESSFUL"

;;; =====	Index variables
I_InRDZone_SectorNo	dw	19
I_InOneSector		dw	16
I_InRDEntry		dw	11
