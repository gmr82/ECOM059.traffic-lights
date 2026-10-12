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
.def temp2 = r19
.def count_aux = r20

; Limite de estados
.set state_limit = 12

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
	ldi temp, $3F
	out DDRB, temp

	; Configura como saída de 0 - 5 para a porta C
	ldi temp, $3F
	out DDRC, temp

	; Configura como saída de 2 - 7 para a porta D
	ldi temp, $FC
	out DDRD, temp
	; ----------------------------------------------------------

	; Carregamento inicial da entrada
	rcall charge_leds

	; Carregamento inicial da qtd de vezes que vai rodar a miséria
	rcall charge_runtimes

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

	; Verifica se count_aux tá zerado pra passar pro próximo estado
	cpi count_aux, 0
	breq proximo_estado

	; Decrementa o miserável
	dec count_aux

	; Verifica se tá no estado que o vermelho de pedestres pisca pra piscar ele
	cpi state_count, 2
	brne exit

	; Seta 1 no bit 3 do PIND
	; A malandragem é que se escrever 1 no PIND ele inverte o valor do bit
	; Se estava 0 (LED apagado), vira 1 (LED aceso)
	; Se estava 1 (LED aceso), vira 0 (LED apagado)
	sbi PIND, 3

	rjmp exit


	proximo_estado:
		; Passa pro próximo estado
		inc state_count

		; Verifica se chegou ao último estado
		cpi state_count, state_limit
		; Caso não pula pra carregar o próximo estado
		brlo estado_valido

		; Volta pro estado inicial
		clr state_count

	
	; Carrega o próximo estado
	estado_valido:
		; Carrega os leds
		rcall charge_leds
		
		; ---- Carrega o tempo ----
		; Para o timer a pauladas
		ldi temp, ((WGM >> 2) << WGM12)
		sts TCCR1B, temp
		
		; Evita problemas com os delays em que o delay anterior é maior do que o próximo
		; Segurança pra não perder o estado
		; Basicamente só joga o contador pra 0
		clr temp
		sts TCNT1H, temp
		sts TCNT1L, temp
		
		; Carrega o tempo
		rcall charge_time

		; Ressucita o poço de vacilo na base da bicuda
		ldi temp, ((WGM>>2)<<WGM12)|(prescale<<CS10)
		sts TCCR1B, temp
		; ----------------------------------------------------------

		; Carregamento inicial da qtd de vezes que vai rodar a miséria
		rcall charge_runtimes

	; Saida
	; Despusha o SREG
	exit:
		pop temp
		out SREG, temp
		pop temp

	reti
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

	; Carrega os leds do estado
	lpm temp, Z+ ; Lê o menos significativo
	lpm temp2, Z ; Lê o mais significativo

	; Carrega 6 leds na porta B (De 0 - 5)
	push temp
	; Mascara pra pegar os 6 bits
	andi temp, $3F
	out PORTB, temp
	pop temp

	; Gambiarra pra pegar os dois últimos bits que não foram para PORTB
	; O lsl desloca os bits para << e joga o bit 7 no carry
	; O rol desloca os bits de temp2 para << e joga o carry no bit 0
	lsl temp
	rol temp2
	lsl temp
	rol temp2

	; Carrega mais 6 leds na porta C (De 0 - 5)
	mov temp, temp2
	; Mascara pra pegar os 6 bits
	andi temp, $3F
	out PORTC, temp

	; Troca os 4 primeiros bits com os últimos 4 bits
	swap temp2
	; Mascara pra pegar os 2 bits
	andi temp2, $0C
	; Pega o que tá na porta D
	in temp, PORTD
	; Zera só o que tiver nos bits que queremos
	andi temp, $F3
	; Junta com o que tem no temp 2
	or temp, temp2
	; Escreve na porta D
	out PORTD, temp
	; ----------------------------------------------------------

	ret
; ============================================================


; ============================================================
; Carrega o mapeamento dos timers
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

	lpm temp2, Z+ ; Lê o byte baixo
	lpm temp, Z ; Lê o byte alto

	; Carrega o myte mais significativo do top
	sts OCR1AH, temp
	; Carrega o byte menos significativo do top
	sts OCR1AL, temp2

	ret
; ============================================================


; ============================================================
; Carrega a quantidade de vezes que cada interrupção vai rodar
; ============================================================
charge_runtimes:
	; Carregando o top inicial em Z
	ldi ZH, high(qtd_runs << 1)
	ldi ZL, low(qtd_runs << 1)

	; Funciona igual ao carregamento do próximo estado
	add ZL, state_count
	clr temp
	adc ZH, temp

	; Carrega o byte menos significativo do top
	lpm count_aux, z

	ret
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
	; 8 de 0.5 segundos
	.dw 7812
	
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
; Mapeamento da quantidade de vezes que vai acontecer as interrupções
; ============================================================
qtd_runs:
; Definindo os limites de execuções, algumas interrupções terão que rodar mais vezes
; É o caso do estado 2 em que o timer precisa bater 12s mas o maldito timer só sabe contar até 4.2
; Tive que botar pra repetir no 3 só pra ele ficar piscando D:
.db 0, 2, 8, 0, 10, 0, 0, 14, 0, 0, 9, 0
; ============================================================