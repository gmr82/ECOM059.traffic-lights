;
; semaforoforo.asm
;
; Created: 07/10/2026 11:25:39
; Authors :


; Determina um segmento de código para a FLASH
.cseg

; Manda PC para o endereço 0
.org 0

; Define um registrador para armazenar o contador de estados
.def state_count = r16
.def segundos = r17

; Registrador auxiliar
.def temp = r18
.def count_aux = r19

; ---- Define limites ----
; Limite de estados
.set state_limit = 12

; Limite de execuções do estado 2
.set state2_limit = 3

; Limite de execuções do estado 5
.set state5_limit = 5

; Limite de execuções do estado 8
.set state8_limit = 15

; Limite de execuções do estado 11
.set state11_limit = 10
; ----------------------------------------------------------

; Pula para o inicializador do maldito programa
jmp reset

; Move o PC para o endereço da interrupção do timer
.org OC1Aaddr
; Desvia para a subrotina de tratamento do timer
rjmp OCI1A_Interrupt

; ============================================================
; Inicia todos os parâmetros
; ============================================================
reset:
	; ---- Inicia a pilha para podermos utilizar subrotinas ----
	ldi temp, high(RAMEND)
	out SPH, temp
	ldi temp, low(RAMEND)
	out SPL, temp
	; ----------------------------------------------------------

	; zera state_count
	clr state_count

	; Fixa o prescale máximo que essa bagaça usa, pelo amor de Deus... É muito pouco D:
	.equ prescale = 0b0101

	; Pra configurar o timer no modo ctc (contar tanto cansa)
	.equ WGM = 0b0100

	; ---- Configura porta como saída ----
	; !! AJUSTAR DEPOIS
	; Configura como saída de 0 - 5 para a porta B
	ldi temp, $7F
	out DDRB, temp

	; Configura como saída de 0 - 5 para a porta C
	ldi temp, $7F
	out DDRC, temp

	; Configura como saída de 2 - 8 para a porta D
	ldi temp, $FC
	out DDRD, temp
	; ----------------------------------------------------------

	; ---- Carregamento inicial da entrada ----
	rcall charge_leds

	; ---- Configura inicialmente o timer ----
	; Carregando o top inicial em Z
	rcall charge_time

	;Habilita as interrupções do timer
	;Carrega o valor do registrador de controle do timer, evita carregar bagunça no TIMSK1
	lds temp, TIMSK1
	;Seta OCIE1A para 1, habilitando as interrupções via timer
	sbr temp, 1 << OCIE1A
	;Carrega para o registrador de controle do timer
	sts TIMSK1, temp

	; Configurar o timer bolado pra contar (maldito só sabe contar até 4.12s)
	; WGM&0b11 = 0b0100 & 0b0011 = 0b0000 
	ldi temp, ((WGM&0b11) << WGM10)
	sts TCCR1A, temp

	;2 bits mais significativos de WGM e seleção de clock
	; WGM >> 2 = 0b0100 >> 2 = 0b0001
	; (WGM >> 2) << WGM12 = (0b0001 << 3) = 0b0001000
	; (PRESCALE << CS10) = 0b101 << 0 = 0b101
	; 0b0001000 | 0b101 = 0b0001101
	ldi temp, ((WGM>>2)<<WGM12)|(prescale << CS10)
	sts TCCR1B, temp
	; ----------------------------------------------------------

	; Habilita globalmente as interrupções
	sei
; ============================================================
	

; ============================================================
; Looping principal
; ============================================================
loop:
	jmp loop

; ============================================================


; ============================================================
; Tratamendo da interrupção
; ============================================================
OCI1A_Interrupt:
	; conceitualmente salvando o sreg ('_')
	push temp
	in temp, SREG
	push temp

	; Passa pro próximo estado
	inc state_count

	; Verifica se chegou ao último estado
	cpi state_count, state_limit
	; Caso não pula pra carregar o próximo estado
	brlo estado_valido

	; Volta pro estado inicial
	clr state_count

	; Atualiza o estado
	estado_valido:
		; ---- Carrega o próximo estado ----
		; Carrega os leds
		rcall charge_leds
		
		; Carrega o tempo
		rcall charge_time
		; ----------------------------------------------------------

	; Saida
	; Despusha o SREG
	pop temp
	out SREG, temp
	pop temp

	reti
; ============================================================


; ============================================================
; Mapeamento dos leds marotos

; StoN
; Semaforo 1: verde (bit 0), amarelo (bit 1), vermelho (bit 2)
; StoW
; Semaforo 2: verde (bit 3), amarelo (bit 4), vermelho (bit 5)
; WtoSaN
; Semaforo 3: verde (bit 6), amarelo (bit 7), vermelho (bit 8)
; NtoWaS
; Semaforo 4: verde (bit 9), amarelo (bit 10), vermelho (bit 11)
; Nc+Sc
; Semaforo 5: verde (bit 12), vermelho(bit 13)
; ============================================================
; Semaforo 1
.equ S1_G = (1 << 0)
.equ S1_Y = (1 << 1)
.equ S1_R = (1 << 2)

; Semaforo 2
.equ S2_G = (1 << 3)
.equ S2_Y = (1 << 4)
.equ S2_R = (1 << 5)

; Semaforo 3
.equ S3_G = (1 << 6)
.equ S3_Y = (1 << 7)
.equ S3_R = (1 << 8)


; Semaforo 4
.equ S4_G = (1 << 9)
.equ S4_Y = (1 << 10)
.equ S4_R = (1 << 11)

; Semaforo 5
.equ S5_G = (1 << 12)
.equ S5_R = (1 << 13)


mapeamento:
	; Estado 1
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 2
	.dw S1_R|S2_R|S3_R|S4_R|S5_G 
	; Estado 3
	; O de pedestre pisca
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 4
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 5
	.dw S1_G|S2_G|S3_R|S4_R|S5_R
	; Estado 6
	.dw S1_G|S2_Y|S3_R|S4_R|S5_R
	; Estado 7
	.dw S1_G|S2_R|S3_R|S4_R|S5_R
	; Estado 8
	.dw S1_G|S2_R|S3_R|S4_G|S5_R
	; Estado 9
	.dw S1_Y|S2_R|S3_R|S4_Y|S5_R
	; Estado 10
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 11
	.dw S1_R|S2_R|S3_G|S4_R|S5_R
	; Estado 12
	.dw S1_R|S2_R|S3_Y|S4_R|S5_R
; ============================================================


; ============================================================
; Mapeamento dos tops :)
; ============================================================
tops:
	; Estado 1
	; 1 de 1 segundo
	.dw 15624

	; Estado 2
	; 3 de 4 segundos
	.dw 62499
	
	; Estado 3
	; 1 de 4 segundos
	.dw 62499
	
	; Estado 4
	; 1 de 2 segundos
	.dw 31249
	
	; Estado 5
	; 11 de 2 segundos
	.dw 31249
	
	; Estado 6
	; 1 de 4 segundos
	.dw 62499
	
	; Estado 7
	; 1 de 1 segundo
	.dw 15624

	; Estado 8
	; 15 de 4 segundos
	.dw 62499
	
	; Estado 9
	; 1 de 4 segundos
	.dw 62499

	; Estado 10
	; 1 de 1 segundo
	.dw 15624

	; Estado 11
	; 10 de aproximadamente 2.5 segundos
	.dw 39062

	; Estado 12
	; 1 de 4 segundos
	.dw 62499
; ============================================================


; ============================================================
; Carrega o mapeamento dos leds
; ============================================================
charge_leds:
	; Configurando z com o mapeamento inicial
	ldi ZH, high(mapeamento << 1)
	ldi ZL, low(mapeamento << 1)

	; Multiplica o state_count por 2
	mov temp, state_count
	lsl temp

	; Incrementa para pegar o indice certo do mapeamento
	add ZL, temp
	clr temp
	adc ZH, temp

	; Carrega a primeira leva de leds pra maldita porta B
	lpm temp, Z+
	; Joga a configuração de z na porta B como saída, faz o led ligar 'o'
	out PORTB, temp

	; Carrega a segunda leva de leds para a maldita porta C
	lpm temp, z
	; Joga a configuração de z na porta C como saída, faz o led ligar 'o'
	out PORTC, temp
	; ----------------------------------------------------------

	ret
; ============================================================


; ============================================================
; Carrega o mapeamento dos leds
; ============================================================
charge_time:
	; Carregando o top inicial em Z
		ldi ZH, high(tops << 1)
		ldi ZL, low(tops << 1)

		; Artimanha pra multiplicar por 2
		; Precisa dessa miséria pra ele pegar a próxima palavra certinha do "vetor" tops
		; O caba não deixa fazer << 1 só porque state_count é registrador :(
		mov temp, state_count
		lsl temp

		; Funciona igual ao carregamento do próximo estado
		add ZL, temp
		clr temp
		adc ZH, temp

		; Carrega o byte menos significativo do top
		lpm temp, z+
		sts OCR1AL, temp
		; Carrega o myte mais significativo do top
		lpm temp, z
		sts OCR1AH, temp

		ret
; ============================================================