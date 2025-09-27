SYSSIZE = 0x3000

SETUPLEN  = 4

BOOTSEG   = 0x7c0

INITSEG   = 0x9000

SETUPSEG  = 0x9020

SYSSEG    = 0x1000

ENDSEG    = SYSSEG + SYSSIZE

ROOT_DEV  = 0x000

.code16
.text

.global _start
_start:
	jmpl $BOOTSEG, $start2

start2:
	/* DS指向源数据（引导扇区），ES指向目标地址（内核加载位置） */
	movw $BOOTSEG, %ax /* 将BOOTSEG（引导扇区地址）加载到ax */
	movw %ax, %ds      /* 设置数据段（ds）为BOOTSEG */
	movw $INITSEG, %ax /* 将INITSEG（内核加载地址）加载到ax */
	movw %ax, %es      /* 设置附加段（es）为INITSEG */

	/* 准备从DS:SI（源地址）复制到ES:DI（目标地址） */
	movw $256, %cx     /* 设置计数器cx为256（复制128个16位数据） */
	subw %si, %si      /* 清空SI（源索引指针） */
	subw %di, %di      /* 清空DI（目标索引指针） */

	rep
	movsw              /* 重复执行16位数据移动（共128次） */

	jmpl $INITSEG, $go

go:
	movw %cs, %ax     /* 将代码段基址加载到ax */
	movw %ax, %ds     /* 设置数据段（ds）与cs相同 */
	movw %ax, %es     /* 设置附加段（es）与CS相同 */
	movw %ax, %ss     /* 设置堆栈段（ss）与CS相同 */
	movw $0xFF00, %sp /* 设置堆栈指针（sp）为0xFF00（位于当前段的高地址） */

load_setup:
	/* 将setup模块加载进内存 */
	movw $0x0000, %dx   /* dl代表驱动器号，0为软盘，1为硬盘；dh代表磁头号 */
	movw $0x0002, %cx   /* ch代表柱面号的低8位；cl的0-5位代表开始扇区号，6-7位代表磁道号的高两位 */
	movw $0x0200, %bx   /* 缓冲区地址（0x0200） */
	movb $SETUPLEN, %al /* 需要读取的扇区数量 */
	movb $0x02,   %ah   /* 功能号（02表示读扇区） */
	int  $0x13          /* 调用BIOS中断 */
	jnc  ok_load_setup
	movw $0x0000, %dx
	movw $0x0000, %ax
	int  $0x13
	jmp  load_setup

ok_load_setup:
	movb $0x00, %dl
	movw $0x0800, %ax
	int  $0x13
	movb $0x00, %ch
	movw %cx, %cs:sectors
	movw $INITSEG, %ax
	movw %ax, %es

	movw $SYSSEG, %ax
	movw %ax, %es
	call read_it           /* 检查ES寄存器的段基址是否位于低1MB内存区域 */
	call kill_motor        /* 关闭软盘驱动器的马达‌ */

	jmp root_defined       /* 暂时先不执行检测根设备 */

	movw %cs:root_dev, %ax /* 加载根设备号到ax */
	cmpw $0, %ax           /* 比较ax是否为0 */
	jne  root_defined      /* 若不为0，跳转到root_defined（根设备已定义） */
	movw %cs:sectors, %bx  /* 加载磁盘总扇区数到bx */
	movw $0x0208, %ax      /* 设置ax为0x0208（假设为设备号） */
	cmpw $15, %bx          /* 检查总扇区数是否为15 */
	je   root_defined      /* 若相等，跳转到root_defined（设备0x0208为根设备） */
	movw $0x021c, %ax      /* 否则尝试设备0x021c */
	cmpw $18, %bx          /* 检查总扇区数是否为18 */
	je   root_defined      /* 若相等，确认设备0x021c为根设备 */
undef_root:
	jmp  undef_root
root_defined:
	mov  %ax, %cs:root_dev

	movw %cs, %ax
	movw %ax, %ds
	movw %ax, %es

	movw $0x600, %ax
	movw $0x700, %bx
	movw $0x0,   %cx
	movw $0x184f,%dx
	int  $0x10

	movw $msg, %ax
	movw %ax, %bp
	movw $0x01301, %ax
	movw $0x0c, %bx
	movw $23, %cx
	movw $0, %dx
	int  $0x010

	jmpl $SETUPSEG, $0

sread:
	.word 1+SETUPLEN
head:
	.word 0
track:
	.word 0

/* 检查ES寄存器的段基址是否位于低1MB内存区域 */
read_it:
	movw %es, %ax
	testw $0x0fff, %ax
die:
	jne die
	xor %bx, %bx
rp_read:
	movw %es, %ax
	cmpw $ENDSEG, %ax
	jb   ok1_read
	ret
ok1_read:
	movw %cs:sectors, %ax
	subw sread, %ax
	movw %ax, %cx
	shlw $9,  %cx
	addw %bx, %cx
	jnc  ok2_read
	je   ok2_read
	xorw %ax, %ax
	subw %bx, %ax
	shrw $9,  %ax
ok2_read:
	call read_track
	movw %ax, %cx
	addw sread, %ax
	cmpw %cs:sectors, %ax
	jne  ok3_read
	movw $1, %ax
	subw head, %ax
	jne  ok4_read
	incw track
ok4_read:
	movw %ax, head
	xorw %ax, %ax
ok3_read:
	movw %ax, sread
	shlw $9,  %cx
	addw %cx, %bx
	jnc  rp_read
	movw %es, %ax
	addw $0x1000, %ax
	movw %ax, %es
	xorw %bx, %bx
	jmp  rp_read

read_track:
	pushw %ax
	pushw %bx
	pushw %cx
	pushw %dx
	movw  track, %dx
	movw  sread, %cx
	incw  %cx
	movb  %dl, %ch
	movw  head, %dx
	movb  %dl, %dh
	movb  $0, %dl
	andw  $0x0100, %dx
	movb  $2, %ah
	int   $0x13
	jc    bad_rt
	popw  %dx
	popw  %cx
	popw  %bx
	popw  %ax
	ret
bad_rt:
	movw $0x0, %ax
	movw $0x0, %dx
	int  $0x13
	popw %dx
	popw %cx
	popw %bx
	popw %ax
	jmp read_track

/* 关闭软盘驱动器的马达‌ */
kill_motor:
	pushw %dx
	movw  $0x3f2, %dx
	movb  $0,  %al
	outb  %al, %dx
	popw  %dx
	ret

sectors:
	.word 0

msg:
.byte 13, 10
.ascii "Linux is booting..."
.byte 13, 10
.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xaa55

