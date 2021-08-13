%include "/usr/local/share/csc314/asm_io.inc"


; the file that stores the initial state
%define BOARD_FILE 'board.txt'
%define TEMPLE 'temple.txt'
%define MART 'mart.txt'
%define LOTTO 'lotto.txt'
%define MOUNTAIN 'mountain.txt'

; how to represent everything
%define WALL_CHAR '#'
%define WORLD_WALL0 '/'
%define WORLD_WALL1 '\'
%define WORLD_WALL2 '_'
%define WORLD_WALL3 '|'
%define GRASS '"'
%define PLAYER_CHAR 'O'

; the size of the game screen in characters
%define HEIGHT 20
%define WIDTH 40

; the player starting position.
; top left is considered (0,0)
%define STARTX 18
%define STARTY 14

; these keys do things
%define EXITCHAR 'x'
%define UPCHAR 'f'
%define LEFTCHAR 'r'
%define DOWNCHAR 's'
%define RIGHTCHAR 't'


segment .data

	; used to fopen() the board file defined above
	board_file			db BOARD_FILE,0
	temple				db TEMPLE,0
	mart		 		db MART,0
	lotto				db LOTTO,0
	mountain			db MOUNTAIN,0

	; used to change the terminal mode
	mode_r				db "r",0
	raw_mode_on_cmd		db "stty raw -echo",0
	raw_mode_off_cmd	db "stty -raw echo",0

	; called by system() to clear/refresh the screen
	clear_screen_cmd	db "clear",0

	; things the program will print
	help_str			db 13,10,"Controls: ", \
							UPCHAR,"=UP / ", \
							LEFTCHAR,"=LEFT / ", \
							DOWNCHAR,"=DOWN / ", \
							RIGHTCHAR,"=RIGHT / ", \
							EXITCHAR,"=EXIT", \
							13,10,10,0
	mart_str	db "Welcome to the Poke Mart! Would you like to buy a poke ball or a great ball?",10,13,0
	mart_no_money	db "If you do not have enough money, try the lotto!",10,13,0
	mart_choices	db "(p)oke ball | (g)reat ball | (n)o",10,13,0
	poke_coins	db "Poke Coins: %d",10,13,0
	poke_counter	dd 0

	lotto_str	db "You now have %d Poke Coins!",10,13,0
	
	encounter_str	db "You ran into a %s!",10,13,0
	encounter_choices db "(c)atch or (r)un?",10,13,0
	
	balls_str	db "Poke Balls: %d",10,13,0
	balls_counter	dd 0
	diglet		db "Diglet",0
	catch_str	db "You caught a %s! You gained $11.",10,13,0
	no_balls	db "You don't have any poke balls! They are available at the Poke Mart.",10,13,0

segment .bss

	; this array stores the current rendered gameboard (HxW)
	board	resb	(HEIGHT * WIDTH)
	mart_board resb (HEIGHT * WIDTH)
	lotto_board resb (HEIGHT * WIDTH)
	mountain_board resb (HEIGHT * WIDTH)

	; these variables store the current player position
	xpos	resd	1
	ypos	resd	1

segment .text

	global	asm_main
	global  raw_mode_on
	global  raw_mode_off
	global  init_board
	global  init_mart
	global 	init_lotto
	global 	init_temple
	global	init_mountain
	global  render

	extern	system
	extern	putchar
	extern	getchar
	extern	printf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose
	extern 	rand

asm_main:
	enter	0,0
	pusha
	;***************CODE STARTS HERE***************************

	; put the terminal in raw mode so the game works nicely
	call	raw_mode_on

	; read the game board file into the global variable
	call	init_board

	; set the player at the proper start position
	mov		DWORD [xpos], STARTX
	mov		DWORD [ypos], STARTY

	; the game happens in this loop
	; the steps are...
	;   1. render (draw) the current board
	;   2. get a character from the user
	;	3. store current xpos,ypos in esi,edi
	;	4. update xpos,ypos based on character from user
	;	5. check what's in the buffer (board) at new xpos,ypos
	;	6. if it's a wall, reset xpos,ypos to saved esi,edi
	;	7. otherwise, just continue! (xpos,ypos are ok)
	game_loop:

		; draw the game board
		call	render

		; get an action from the user
		call	getchar

		; store the current position
		; we will test if the new position is legal
		; if not, we will restore these
		mov		esi, [xpos]
		mov		edi, [ypos]

		; choose what to do
		cmp		eax, EXITCHAR
		je		game_loop_end
		cmp		eax, UPCHAR
		je 		move_up
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, DOWNCHAR
		je		move_down
		cmp		eax, RIGHTCHAR
		je		move_right
		jmp		input_end			; or just do nothing

		; move the player according to the input character
		move_up:
			dec		DWORD [ypos]
			jmp		input_end
		move_left:
			dec		DWORD [xpos]
			jmp		input_end
		move_down:
			inc		DWORD [ypos]
			jmp		input_end
		move_right:
			inc		DWORD [xpos]
		input_end:

		; (W * y) + x = pos

		; compare the current position to the wall character
		mov		eax, WIDTH
		mul		DWORD [ypos]
		add		eax, [xpos]
		lea		eax, [board + eax]
		cmp		BYTE [eax], WALL_CHAR
		je invalid	
		cmp		BYTE [eax], WORLD_WALL0
		je invalid	
		cmp		BYTE [eax], WORLD_WALL1
		je invalid
		cmp		BYTE [eax], WORLD_WALL2
		je invalid	
		cmp		BYTE [eax], WORLD_WALL3
		je invalid	
		jmp valid_move	
		invalid:; opps, that was an invalid move, reset
			mov		DWORD [xpos], esi
			mov		DWORD [ypos], edi
		valid_move:
			; compare current position to mart door on board
			cmp DWORD [ypos], 16
			jne lottocheck
			cmp DWORD [xpos], 28
			jne lottocheck	
				call init_mart
				martloop:
				call mrender
				call getchar
				cmp eax, 'n'
				je game_loop
				cmp eax, 'p'
				je buy_poke
				cmp eax, 'g'
				je buy_great
				jmp martloop
					buy_poke:
					cmp DWORD [poke_counter], 0
					je martloop
					sub DWORD [poke_counter], 10
					inc DWORD [balls_counter]
					jmp martloop
					buy_great:
					cmp DWORD [poke_counter], 0
					je martloop
					sub DWORD [poke_counter], 20
					inc DWORD [balls_counter]
					jmp martloop
			lottocheck:
			cmp DWORD [ypos], 14
			jne mountaincheck
			cmp DWORD [xpos], 5
			jne mountaincheck
				call init_lotto
				lottoloop:
				call lrender
				call getchar
				cmp eax, 'x'
				je game_loop
			mountaincheck:
			cmp DWORD [ypos], 10
			jne templecheck
			cmp DWORD [xpos], 35
			jne templecheck
				call init_mountain
				mountainloop:
				call morender
				call getchar
				cmp eax, 'r'
				je game_loop
				jmp mountainloop
			templecheck:
							
	jmp	game_loop
	game_loop_end:

	; restore old terminal functionality
	call raw_mode_off

	;***************CODE ENDS HERE*****************************
	popa
	mov		eax, 0
	leave
	ret

; === FUNCTION ===
raw_mode_on:

	push	ebp
	mov		ebp, esp

	push	raw_mode_on_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; === FUNCTION ===
raw_mode_off:

	push	ebp
	mov		ebp, esp

	push	raw_mode_off_cmd
	call	system
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; ================ BOARD ===================
init_board:
	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	board_file
	call	fopen
	add		esp, 8
	mov		DWORD [ebp-4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp-8], 0
	read_loop:
	cmp		DWORD [ebp-8], HEIGHT
	je		read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp-8]
		lea		ebx, [board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp-4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp-4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp-8]
	jmp		read_loop
	read_loop_end:

	; close the open file handle
	push	DWORD [ebp-4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

render:
	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; print poke coins
	push DWORD [poke_counter]
	push poke_coins
	call printf
	add esp, 8

	; print poke balls
	push DWORD [balls_counter]
	push balls_str
	call printf
	add esp, 8 

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp-4], 0
	y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp-8], 0
		x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		print_board
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				jmp		print_end
			print_board:
				; otherwise print whatever's in the buffer
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, 0
				mov		bl, BYTE [board + eax]
				push	ebx
			print_end:
			call	putchar
			add		esp, 4

		inc		DWORD [ebp-8]
		jmp		x_loop_start
		x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		y_loop_start
	y_loop_end:


	mov		esp, ebp
	pop		ebp
	ret

; ================ MART ===================
init_mart:

	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	mart
	call	fopen
	add		esp, 8
	mov		DWORD [ebp-4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp-8], 0
	m_read_loop:
	cmp		DWORD [ebp-8], HEIGHT
	je		m_read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp-8]
		lea		ebx, [mart_board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp-4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp-4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp-8]
	jmp		m_read_loop
	m_read_loop_end:

	; close the open file handle
	push	DWORD [ebp-4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

mrender:
	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; print poke coins
	push DWORD [poke_counter]
	push poke_coins
	call printf
	add esp, 8

	; print poke balls
	push DWORD [balls_counter]
	push balls_str
	call printf
	add esp, 8 

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp-4], 0
	m_y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		m_y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp-8], 0
		m_x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		m_x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		m_print_board
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		m_print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				jmp		m_print_end
			m_print_board:
				; otherwise print whatever's in the buffer
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, 0
				mov		bl, BYTE [mart_board + eax]
				push	ebx
			m_print_end:
			call	putchar
			add		esp, 4

		inc		DWORD [ebp-8]
		jmp		m_x_loop_start
		m_x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		m_y_loop_start
	m_y_loop_end:

	push mart_str
	call printf
	add esp, 4

	push mart_choices
	call printf
	add esp, 4

	push mart_no_money
	call printf
	add esp, 4

	mov		esp, ebp
	pop		ebp
	ret

; ================ LOTTO ===================
init_lotto:
	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	lotto
	call	fopen
	add		esp, 8
	mov		DWORD [ebp-4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp-8], 0
	l_read_loop:
	cmp		DWORD [ebp-8], HEIGHT
	je		l_read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp-8]
		lea		ebx, [lotto_board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp-4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp-4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp-8]
	jmp		l_read_loop
	l_read_loop_end:

	; close the open file handle
	push	DWORD [ebp-4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

lrender:
	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; print poke coins
	push DWORD [poke_counter]
	push poke_coins
	call printf
	add esp, 8

	; print poke balls
	push DWORD [balls_counter]
	push balls_str
	call printf
	add esp, 8 

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp-4], 0
	l_y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		l_y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp-8], 0
		l_x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		l_x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		l_print_board
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		l_print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				jmp		l_print_end
			l_print_board:
				; otherwise print whatever's in the buffer
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, 0
				mov		bl, BYTE [lotto_board + eax]
				push	ebx
			l_print_end:
			call	putchar
			add		esp, 4

		inc		DWORD [ebp-8]
		jmp		l_x_loop_start
		l_x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		l_y_loop_start
	l_y_loop_end:

	; gen rand number
	xor eax, eax
	call rand
	; put in lotto string
	; add to poke coins
	
	mov BYTE [poke_counter], al
	push DWORD [poke_counter]
	push lotto_str
	call printf
	add esp, 8

	mov		esp, ebp
	pop		ebp
	ret

; ================ MOUNTAIN ===================
init_mountain:
	push	ebp
	mov		ebp, esp

	; FILE* and loop counter
	; ebp-4, ebp-8
	sub		esp, 8

	; open the file
	push	mode_r
	push	mountain
	call	fopen
	add		esp, 8
	mov		DWORD [ebp-4], eax

	; read the file data into the global buffer
	; line-by-line so we can ignore the newline characters
	mov		DWORD [ebp-8], 0
	mo_read_loop:
	cmp		DWORD [ebp-8], HEIGHT
	je		mo_read_loop_end

		; find the offset (WIDTH * counter)
		mov		eax, WIDTH
		mul		DWORD [ebp-8]
		lea		ebx, [mountain_board + eax]

		; read the bytes into the buffer
		push	DWORD [ebp-4]
		push	WIDTH
		push	1
		push	ebx
		call	fread
		add		esp, 16

		; slurp up the newline
		push	DWORD [ebp-4]
		call	fgetc
		add		esp, 4

	inc		DWORD [ebp-8]
	jmp		mo_read_loop
	mo_read_loop_end:

	; close the open file handle
	push	DWORD [ebp-4]
	call	fclose
	add		esp, 4

	mov		esp, ebp
	pop		ebp
	ret

morender:
	push	ebp
	mov		ebp, esp

	; two ints, for two loop counters
	; ebp-4, ebp-8
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print the help information
	push	help_str
	call	printf
	add		esp, 4

	; print poke coins
	push DWORD [poke_counter]
	push poke_coins
	call printf
	add esp, 8

	; print poke balls
	push DWORD [balls_counter]
	push balls_str
	call printf
	add esp, 8 

	; outside loop by height
	; i.e. for(c=0; c<height; c++)
	mov		DWORD [ebp-4], 0
	mo_y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		mo_y_loop_end

		; inside loop by width
		; i.e. for(c=0; c<width; c++)
		mov		DWORD [ebp-8], 0
		mo_x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		mo_x_loop_end

			; check if (xpos,ypos)=(x,y)
			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		mo_print_board
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		mo_print_board
				; if both were equal, print the player
				push	PLAYER_CHAR
				jmp		mo_print_end
			mo_print_board:
				; otherwise print whatever's in the buffer
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, 0
				mov		bl, BYTE [mountain_board + eax]
				push	ebx
			mo_print_end:
			call	putchar
			add		esp, 4

		inc		DWORD [ebp-8]
		jmp		mo_x_loop_start
		mo_x_loop_end:

		; write a carriage return (necessary when in raw mode)
		push	0x0d
		call 	putchar
		add		esp, 4

		; write a newline
		push	0x0a
		call	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		mo_y_loop_start
	mo_y_loop_end:

	push diglet
	push encounter_str
	call printf
	add esp, 8

	push encounter_choices
	call printf
	add esp, 4

	call getchar
	cmp eax, 'r'
	je game_loop
	cmp eax, 'c'
	jne mo_end

	cmp BYTE [balls_counter], 0
	jne mo_caught
	push no_balls
	call printf
	add esp, 4
	jmp mo_end

	mo_caught:
	push diglet
	push catch_str
	call printf
	add esp, 8

	dec DWORD [balls_counter]
	add DWORD [poke_counter], 11

	mo_end:
	mov		esp, ebp
	pop		ebp
	ret

