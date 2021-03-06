; race game state - main game

PLAYERWIDTH    = $08
PLAYERHEIGHT   = $08
TURNSPEED      = $10
SPRITECARBASE  = $08 ; start of car sprites
CARSPRITE      = $0200
FINISHLINEX    = $92

playerx        .rs 1
playery        .rs 1
rotationindex  .rs 1
playerrotation .rs 1
playerrottimer .rs 1
tempmovement   .rs 1 ; used for (I never finished this comment wtf)
playeraccel    .rs 1 ; increases with up/down
playervel      .rs 1 ; moves player when it overflows
drivespeed     .rs 1
negativevel    .rs 1
; stuff to deal with getting stuck in walls because I'm too dumb
didcollide     .rs 1 ; did we collide this frame?
colframes      .rs 1 ; how many frames in a row are we inside something
noclplayerx    .rs 1 ; last x pos where we didn't collide
noclplayery    .rs 1 ; last y pos where we didn't collide

timertilehigh  .rs 1
timertilelow   .rs 1
laptilehigh    .rs 1
laptilelow     .rs 1
cdowntilehigh  .rs 1
cdowntilelow   .rs 1

currentlap     .rs 1
maxlap         .rs 1
lapflag        .rs 1
framebeforex   .rs 1

countdown      .rs 1

timermils      .rs 1
timer1         .rs 1
timer10        .rs 1
timer100       .rs 1

; addresses to load track-specific stuff
trackbgloadlow    .rs 1 ; background address low byte
trackbgloadhigh   .rs 1 ; and high byte
trackwallloadlow  .rs 1 ; walls address low byte
trackwallloadhigh .rs 1 ; and high byte
trackwallcount    .rs 1 ; number of boxes
finishlinex       .rs 1
finishlineytop    .rs 1
finishlineybot    .rs 1

; switch to game state here
startgamestate:
  jsr disablenmi

  lda #STATE_RACE
  sta gamestate

  jsr loadgamestuff
  jsr enablesound

  ; initialize variables and stuff
  lda #$02
  sta rotationindex
  jsr updaterotationfromindex
  lda #$05
  sta countdown

  ; reset things in the case of coming back from end screen
  lda #$00
  sta currentlap
  sta lapflag
  sta timermils
  sta timer1
  sta timer10
  sta timer100
  sta playeraccel

  ; apparently one of these needs to be run twice
  ; to get the icons to show up for some reason
  ; i'm very confused
  jsr updatetimerlabel
  jsr updatelaplabel
  jsr updatelaplabel

  jsr enablenmi
  rts

dogamestate:
  ; do all the background updating before nmi stuff
  jsr updatetimerlabel
  jsr updatelaplabel
  jsr updatecountdownlabel

  jsr enablenmi

  ; update graphics
  jsr updateplayersprite

  ; game logic
  lda countdown
  beq gsrace
  ; still counting down
  jsr docountdown
  jmp nmiend
gsrace:
  lda #$00
  sta didcollide ; reset our collision flag
  lda playerx
  sta framebeforex ; keep track of x before movement

  jsr incrementtimer

  jsr turncooldown
  jsr rotateplayer
  jsr accelerateplayer
  ; driveplayer twice as an easy way to move faster
  jsr driveplayer
  jsr driveplayer
  jsr collideplayer

  jsr carsounds

  jsr fixstuckinwall
  jsr lapcheck
  jsr checkformenubutton
  jmp nmiend

docountdown:
  lda timermils
  clc
  adc #$01
  sta timermils
  cmp #$20
  bne dcdend
  lda #$00
  sta timermils
  dec countdown
  lda #%00000111
  sta $4000
  lda #%11011111
  sta $4002
  lda countdown
  cmp #$01
  beq dcdstartsound
  bcc dcdend
  ; boop boop boop
  ; beeeeeeeeeeeep
  lda #%01111011
  sta $4003
  jmp dcdend
dcdstartsound:
  ; beeeeeeeeeeeep
  lda #%11111001
  sta $4003
dcdend:
  rts

carsounds: ;brrrrrrrrrummmmmmmmmmmmm 
  lda #%01000011
  sta $4000
  lda playeraccel
  beq csstopsound
  sec ; make sure we carry over the last bit
  ror a
  eor #%01111111
  sta $4002
  lda timermils
  and #%00000011
  ora #$00000001 ; keep this bit always on
  sta $4003
  rts
csstopsound: ; no soundarino
  lda #$00
  sta $4002
  sta $4003
  rts

driveplayer:
  lda playervel
  clc
  adc playeraccel
  sta playervel
  bcc dplend
  ; velocity carried over
  jsr updatemovedirections
  lda negativevel
  bne dplreverse
  jsr moveplayerforward
  jmp dplend
dplreverse
  jsr moveplayerbackwards
dplend:
  rts

accelerateplayer:
  lda buttons
  and #%10000000
  beq aplnobutton
  ; when velocity is negative, act like no button is being held down
  lda negativevel
  bne aplnobutton
  lda playeraccel
  cmp drivespeed
  bcs aplend
  inc playeraccel
  inc playeraccel
  jmp aplend
aplnobutton:
  lda playeraccel
  cmp #$00
  beq aplend
  sec
  sbc #$02
  sta playeraccel
  bcs aplend
  lda #$00
  sta playeraccel
aplend:
  ; check if we're moving backwards
  lda negativevel
  beq aplafterreverse
  ; we are moving backwards
  ; if accel is 0 then make it seem like we start going forward
  lda playeraccel
  bne aplafterreverse
  lda #$00
  sta negativevel ; just by setting negative flag to 0
aplafterreverse:
  rts

checkformenubutton:
  lda buttons
  and #%00100000
  beq menubuttonend
  jsr startmenustate
menubuttonend:
  rts

moveplayerforward:
  ; honestly this is all awful and not worth commenting I just wanted the driving to work
  cpx #$00
  bne mplforward2
  dec playerx
mplforward2:
  cpx #$02
  bne mplforward3
  inc playerx
mplforward3:
  cpy #$00
  bne mplforward4
  dec playery
mplforward4:
  cpy #$02
  bne mpfend
  inc playery
mpfend:
  rts

moveplayerbackwards:
  cpx #$00
  bne mplback2
  inc playerx
mplback2:
  cpx #$02
  bne mplback3
  dec playerx
mplback3:
  cpy #$00
  bne mplback4
  inc playery
mplback4:
  cpy #$02
  bne mplbackend
  dec playery
mplbackend:
  rts

collideplayer:
  ; check left wall
  lda playerx
  cmp #$0f
  bcs clpchecktopwall
  lda #$10
  sta playerx
  jsr playercollided
  jmp clpend
clpchecktopwall:
  ; check top wall
  lda playery
  cmp #$0e
  bcs clpcheckrightwall
  lda #$0f
  sta playery
  jsr playercollided
  cmp clpend
clpcheckrightwall:
  ; check right wall
  lda playerx
  cmp #$ea
  bcc clpcheckbottomwall
  lda #$e9
  sta playerx
  jsr playercollided
  cmp clpend
clpcheckbottomwall:
  lda playery
  cmp #$d9
  bcc clpend
  lda #$d8
  sta playery
  jsr playercollided
clpend:
  jsr collidewalls
  rts

collidewalls
  ldx #$00
clwloop:
  jsr roundxupwalls
  ; check left side
  lda playerx
  clc
  adc #PLAYERWIDTH
  cmp [trackwallloadlow],y
  bcc clwloopend
  ; check top side
  iny
  lda playery
  clc
  adc #PLAYERHEIGHT
  cmp [trackwallloadlow],y
  bcc clwloopend
  ; check right side
  iny
  lda playerx
  cmp [trackwallloadlow],y
  bcs clwloopend
  ; check bottom side
  iny
  lda playery
  cmp [trackwallloadlow],y
  bcs clwloopend
  ; WE'VE COLLIDED
  jsr updatemovedirections
  jsr playercollided
  rts ; we can leave this routine
clwloopend:
  inx
  cpx trackwallcount
  bne clwloop
  jsr updatemovedirections
  ; wow collision done
  rts

; supposed to make y = x*4
roundxupwalls:
  ldy #$00
  cpx #$00
  beq rxuwend
  txa
rxuwloop:
  iny
  iny
  iny
  iny
  sec
  sbc #$01
  cmp #$00
  bne rxuwloop
rxuwend:
  rts

; call this when the car hits a wall or something
playercollided:
  lda negativevel
  eor #$01 ; flip between 0 and 1
  ;lda #$01
  sta negativevel
  lda #$01
  sta didcollide ; set flag to keep track that we collided this frame
  ; put car at last non-wall position
  lda noclplayerx
  sta playerx
  lda noclplayery
  sta playery
  ; reduce speed too 
  clc ; make sure carry is clear before rotating
  ror playeraccel ; / 2
  lda playeraccel
  cmp #$20
  bcs plclend
  lda #$20
  sta playeraccel ; make sure accel has a minimum so we're moving if stuck in wall
plclend:
  rts

fixstuckinwall:
  lda didcollide
  beq fswnocollide
  ; we did collide
  lda colframes
  clc
  adc #$01
  sta colframes
  cmp #$10
  bcc fswend
  ; we've been in a wall for 3 frames
  ; so we'll move to our last known non-wall position
  lda noclplayerx
  sta playerx
  lda noclplayery
  sta playery
  lda #$00
  sta colframes
  sta playeraccel
  sta negativevel
  jmp fswend
fswnocollide:
  ; didn't collide this frame
  ; keep track of this position where we're out of a wall
  lda playerx
  sta noclplayerx
  lda playery
  sta noclplayery
  ; reset frame counter
  lda #$00
  sta colframes
fswend:
  rts

lapcheck:
  ; check we're in the finish line vertically
  lda playery
  cmp finishlineytop
  bcc lpcend
  ; >= $bd
  lda playery ; not sure if I need to load this again
  cmp finishlineybot
  bcs lpcend
  ; we are within the lap line vertically
  ; now to check if we passed the finish line
  lda framebeforex
  cmp finishlinex
  bcs lpcwasright
lpcwasleft:
  ; car was left of the finish line before this frame
  lda playerx
  cmp finishlinex
  bcc lpcend ; no crossage
  ; crossed it the correct direction
  lda lapflag
  beq lpcleftend ; lap flag = 0
  ; lap flag = 1
  jsr lapcomplete
lpcleftend:
  lda #$01
  sta lapflag
  jmp lpcend
lpcwasright:
  ; car was right of the finish line before this frame
  lda playerx
  cmp finishlinex
  bcs lpcend ; no crossage
  ; crossed, but the wrong direction
  lda #$00
  sta lapflag ; set lap flag to 0 so we know not to count this as a lap
lpcend:
  rts

lapcomplete:
  inc currentlap
  lda currentlap
  cmp maxlap
  bne lcend
  jsr startendstate
lcend:
  rts

turncooldown:
  ; if left/right isn't down then we can reset
  lda buttons
  and #%00000011
  bne tcdbuttonheld
  lda #$ff
  jmp tcdupdatetimer
tcdbuttonheld:
  ; button is down, count down the cooldown
  lda playerrottimer
  cmp #$ff
  beq tcdend
  ; cooldown timer is < ff
  clc
  adc #TURNSPEED
  bcc tcdupdatetimer
  ; went over $ff
  lda #$ff ; limit it to $ff
tcdupdatetimer:
  sta playerrottimer
tcdend:
  rts

rotateplayer:
  lda buttons
  and #%00000001
  beq plleftturn
  ; right is down
  lda playerrottimer
  cmp #$ff
  bne plleftturn ; only want to turn if the 'cooldown' is up
  jsr plrotateright ; deal with it in this subroutine or whatever it's called
  lda #$00
  sta playerrottimer ; reset turn cooldown
plleftturn:
  lda buttons
  and #%00000010
  beq plturnend
  ; left is down
  lda playerrottimer
  cmp #$ff
  bne plturnend ; only want to turn if the 'cooldown' is up
  jsr plrotateleft
  lda #$00
  sta playerrottimer ; reset turn cooldown
plturnend:
  rts

; left/right rotations are separate because I expected them to be big and used elsewhere
; i.e. collision/bouncing
plrotateright:
  lda rotationindex
  clc
  adc #$01
  cmp #$08
  bcc rrindexfinished
  ; index is >= $08
  lda #$00 ; so we loop
rrindexfinished:
  sta rotationindex
  jsr updaterotationfromindex
  rts

plrotateleft:
  lda rotationindex
  sec
  sbc #$01
  bcs rlindexfinished
  ; underflowed to $ff
  lda #$07 ; go back to highest index
rlindexfinished:
  sta rotationindex
  jsr updaterotationfromindex
  rts

; grabs the direction number from the 'directions' data below
updaterotationfromindex:
  ldx rotationindex
  lda directions,x
  sta playerrotation
  rts

updatemovedirections:
  ; idea here is to adjust x/y to show which directions we need to move
  ; 0 = negative movement, 1 = no movement, 2 = positive movement
  ; this is awful i should figure out how negatives work if they even do natively
  ldx #$01 ; net x movement
  ldy #$01 ; net y movement
  lda playerrotation
  and #%00001000 ; right
  beq mplleftcheck
  inx
mplleftcheck:
  lda playerrotation
  and #%00000100 ; left
  beq mplupcheck
  dex
mplupcheck:
  lda playerrotation
  and #%00000010 ; up
  beq mpldowncheck
  dey
mpldowncheck:
  lda playerrotation
  and #%00000001 ; down
  beq umdfinish
  iny
umdfinish:
  rts

updateplayersprite:
  lda playery
  sta CARSPRITE ; set y pos
  lda playerx
  ldx #$03 ; offset from sprite address for x position
  sta CARSPRITE, x
  ; rotation things
  ldx #$00 ; offset from first car sprite
  lda playerrotation
  and #%00001100 ; left or right
  beq upssetsprite
  inx
  lda playerrotation
  and #%00000011 ; up or down AND left or right so it will be diagonal
  beq upssetsprite
  inx
upssetsprite:
  txa
  clc
  adc #SPRITECARBASE
  ldx #$01 ; offset from start of sprite
  sta CARSPRITE,x
  ; first reset the flippage
  ldx #$02 ; offset for sprite attributes
  lda CARSPRITE,x
  and #%00111111 ; remove the last 2 bits (flips)
  sta CARSPRITE,x
  ; horizontal flip if facing right
  lda playerrotation
  and #%00001000
  beq upsvertflip
  ; are facing right
  lda CARSPRITE,x
  ora #%01000000
  sta CARSPRITE,x
upsvertflip:
  lda playerrotation
  and #%00000001
  beq upsend
  ; facing down
  lda CARSPRITE,x
  ora #%10000000
  sta CARSPRITE,x
upsend:
  rts

incrementtimer:
  lda timermils ; not milliseconds but frames, dumb name
  clc
  adc #$01
  sta timermils
  cmp #$3c ; ~1 second
  bne inctend
  ; 1 second is up
  lda #$00
  sta timermils ; reset frame count to 0
  lda timer1
  clc
  adc #$01
  sta timer1
  cmp #$0a ; roll over from 1 to 2 digits
  bne inctend
  ; rolled over
  lda #$00
  sta timer1 ; reset second count to 0
  lda timer10
  clc
  adc #$01
  sta timer10
  cmp #$0a ; roll over
  bne inctend
  lda #$00 ; reset tens count to 0
  sta timer10
  lda timer100
  clc
  adc #$01
  sta timer100
  cmp #$0a ; rolled over
  bne inctend
  lda #$09 ; cap it at $09
  sta timer100
inctend:
  rts

updatetimerlabel:
  lda $2002 ; start listening for an address
  lda timertilehigh
  sta $2006
  lda timertilelow
  sta $2006
  lda #$0d ; clock icon
  sta $2007
  lda timer100
  sta $2007
  lda timer10
  sta $2007
  lda timer1
  sta $2007
  lda #$fa ; put grass here because there's a phantom 0 for some reason
  sta $2007
  rts

updatelaplabel:
  lda $2002 ; start listening for an address
  lda laptilehigh
  sta $2006
  lda laptilelow
  sta $2006
  lda #$0f ; flag icon
  sta $2007
  lda currentlap
  clc
  adc #$01
  sta $2007
  lda #$10 ; slash
  sta $2007
  lda maxlap
  sta $2007
  rts

updatecountdownlabel:
  lda $2002
  lda cdowntilehigh
  sta $2006
  lda cdowntilelow
  sta $2006
  lda countdown
  bne ucdlend
  lda #$fb
ucdlend:
  sec
  sbc #$01
  sta $2007
  rts

; load background and sprites and stuff
loadgamestuff:
  ; load background
  ; load pointer values
  lda trackbgloadlow;#LOW(track1background)
  sta timermils
  lda trackbgloadhigh;#HIGH(track1background)
  sta timer1 ; use timer stuff as the pointer instead of having its own variable
  lda $2002
  lda #$20
  sta $2006
  lda #$00
  sta $2006
  ldx #$00
  ldy #$00
loadgamebgl1: ; load game background loop 1
loadgamebgl2: ; and 2
  lda [timermils], y
  sta $2007

  iny ; loop2
  cpy #$00
  bne loadgamebgl2 ; keep going til y wraps around to 0
  
  ; gone through 256 times
  inc timer1 ; so we bump up the high byte
  inx
  cpx #$04
  bne loadgamebgl1

  ; load sprites
  ldx #$00
loadgamesprites:
  lda sprites,x
  sta  $0200,x
  inx
  cpx #$04
  bne loadgamesprites
  rts