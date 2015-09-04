''
''
''     LSM9DS1 Gyro/Accel/Magnetometer, LPS25H Barometer SPI driver
''
''     Jason Dorie               
''               
'' Note that this code assumes an 80 MHz clock

' 1 / x = 

' 1_000 = ms
' 1_000_000 = us
' 1_000_000_000 = ns

'    20_000_000 = 50 ns        (one instruction, 4 cycles @ 80MHz)
'    80_000_000 = 80MHz cycle


CON
  _clkmode = xtal1 + pll16x
  _clkfreq = 80_000_000


  HUNDRED_nS  = _clkfreq / 10_000_000  'Number of clock cycles per 100 nanoseconds (8 @ 80MHz)                        
  ONE_uS      = HUNDRED_nS * 10 'Number of clock cycles per 1 microsecond (1000 nanoseconds)

' LED_RESET   = 50 * ONE_uS     'Too big to be a constant, so it's in a variable in the DAT section

'WS2812B Timings
  LED_0_HI    = (ONE_uS * 35)/100       
  LED_0_LO    = (ONE_uS * 90)/100       
  LED_1_HI    = (ONE_uS * 90)/100       
  LED_1_LO    = (ONE_uS * 35)/100       


'WS2812 Timings
'  LED_0_HI    = (ONE_uS * 35)/100       
'  LED_0_LO    = (ONE_uS * 80)/100       
'  LED_1_HI    = (ONE_uS * 70)/100       
'  LED_1_LO    = (ONE_uS * 60)/100       
    

  Gy_Temp = 0
  GyroX = 1
  GyroY = 2
  GyroZ = 3
  AccX = 4
  AccY = 5
  AccZ = 6
  MagX = 7
  MagY = 8
  MagZ = 9
  Alt = 10
  AltTemp = 11
  Timer = 12
  ParamsSize = 13
    

VAR

  long  ins[ParamsSize]         'Temp, GX, GY, GZ, AX, AY, AZ, MX, MY, MZ, Alt, AltTemp, Timer
  long  DriftScale[3]
  long  DriftOffset[3]          'These values will be altered in the EEPROM by the Config Tool and Propeller Eeprom code                       

  long  cog


OBJ

  eeprom : "Propeller Eeprom.spin"


PUB start(ipin, opin, cpin, sgpin, smpin, apin, _LEDPin, _LEDAddr, _LEDCount) : okay

'' Start driver - starts a cog
'' returns false if no cog available
'' may be called again to change settings
''
''   ipin    = pin connected to DIN
''   opin    = pin connected to DOUT
''   cpin    = pin connected to CLK
''   sgpin   = pin connected to CS_AG
''   smpin   = pin connected to CS_M
''   apin    = pin connected to CS on altimeter
''   LEDPin  = pin connected to WS2812B LED array
''   LEDAddr = HUB address of RGB values for LED array (updated constantly)
''   LEDCount= Number of LED values to update  

  'Copy these values from the variables the DAT section so the cog starts with the right settings
  longmove( @DriftScaleGX, @DriftScale[0], 6 ) 

  return startx(@ipin)



PRI startx(ptr) : okay

  stop
  longmove(@ins, ptr, 9)

  return cog := cognew(@entry, @ins) + 1


PUB stop

'' Stop driver - frees a cog

  if cog
    cogstop(cog~ - 1)


PUB in(channel)

'' Read the current value from a channel (0..ParamsSize-1)

  return ins[channel]

PUB Address
'' Get the address of the sensor readings
  return @ins


PUB TempZeroDriftValues

  longmove( @DriftScaleGX, @DriftScale[0], 6 )         'Temporarily back up the values in the DAT section so we can restore them with "ResetDriftValues"
  longfill( @DriftScale[0], 0, 6 )


PUB ResetDriftValues

  longmove( @DriftScale[0], @DriftScaleGX, 6 )


PUB SetDriftValues( ScaleX, ScaleY, ScaleZ, OffsetX, OffsetY, OffsetZ )

  longmove( @DriftScale[0], @ScaleX, 6 )
  longmove( @DriftScaleGX, @ScaleX, 6 )
  eeprom.VarBackup(@DriftScale[0], @DriftScale[0]+24)         ' Copy from VAR to EEPROM



DAT

'*********************************************
'* Assembly language LSM9DS1 + LPS25H driver *
'*********************************************

                        org
'
'
' Entry
'
entry                   mov     t1,par                  'read parameters

                        call    #param                  'setup DIN pin
                        mov     imask,t2

                        call    #param                  'setup DOUT pin
                        mov     omask,t2

                        call    #param                  'setup CLK pin
                        mov     cmask,t2

                        call    #param                  'setup CS_AG pin
                        mov     sgmask,t2

                        call    #param                  'setup CS_M pin
                        mov     smmask,t2

                        call    #param                  'setup CS altimeter pin
                        mov     amask,t2

                        call    #param                  'setup LED pin
                        mov     ledMask,t2

                        call    #param                  'setup LED Address
                        mov     ledAddress, t3

                        call    #param                  'setup LED count
                        mov     ledCount, t3


                        mov     outAddr, par            'Store the address of the parameters array for output

                        mov     driftHubAddr, par
                        add     driftHubAddr, #ParamsSize*4     'Drift array starts (ParamsSize) longs from the beginning of the output params array                        

'Set pin directions
                        or      dira,cmask              'output CLK
                        or      dira,sgmask             'output CS_AG
                        or      dira,smmask             'output CS_M
                        or      dira,amask              'output CS altimeter
                        or      dira,imask              'output SDI

                        or      dira,ledMask            'output LED pin
                        or      outa,ledMask            'bring LED pin high

                        or      outa, sgmask            'bring CS pins high
                        or      outa, smmask
                        or      outa, amask


                        call    #Config_GryoAccelMag    'Configure the gyro and accelerometer registers                        

                        call    #Config_Altimeter       'Configure the altimeter registers                        


                        mov     counter, CNT            'Grab the value of the counter
                        add     counter, loopdelay      'Add the master loop delay


'Main sensor read loop

main_loop
                        mov     LoopTime, cnt
                                 
                        mov     spi_cs_mask, sgmask     'Start with the gyro/accelerometer
                        
                        
                        'mov     spi_reg, #$0f           'Read WhoAmI register
                        'call    #SPI_Read               'Read data from SPI
                        'wrword  spi_data, outAddr       'Write result to hub                        

                        '---- Temperature --------------
                        mov     spi_reg, #$15
                        call    #SPI_ReadWord           'Read the Temperature register
                        mov     OutTemp, spi_data


                        '---- Gyro X -------------------
                        mov     spi_reg, #$18     
                        call    #SPI_ReadWord           'Read the Gyro X register
                        mov     OutGX, spi_data

                        '---- Gyro Y ----
                        mov     spi_reg, #$1A     
                        call    #SPI_ReadWord           'Read the Gyro Y register
                        mov     OutGY, spi_data

                        '---- Gyro Z ----
                        mov     spi_reg, #$1C     
                        call    #SPI_ReadWord           'Read the Gyro Z register
                        mov     OutGZ, spi_data
                        

                        '---- Accel X ------------------
                        mov     spi_reg, #$28     
                        call    #SPI_ReadWord           'Read the Accelerometer X register
                        mov     OutAX, spi_data

                        '---- Accel Y ----
                        mov     spi_reg, #$2A     
                        call    #SPI_ReadWord           'Read the Accelerometer Y register
                        mov     OutAY, spi_data

                        '---- Accel  Z ----
                        mov     spi_reg, #$2C     
                        call    #SPI_ReadWord           'Read the Accelerometer Z register
                        mov     OutAZ, spi_data




                        '---- Magnetometer--------------
                        mov     spi_cs_mask, smmask     'Next, read the magnetometer


                        'mov     spi_reg, #$27           'Read the Magnetometer status register to see if data is ready
                        'call    #SPI_ReadByte

                        'mov     t3, spi_data            'Store to temp register t3            


:Mag_Read_X
'                        test    t3, #1          wc      'X data available?
'              if_nc     jmp     #:Mag_Done_X                                            


                        mov     spi_reg, #$68           'read the Magnetometer X register ($28 | $40 = continuous read mode)              
                        call    #SPI_ReadWord
                        mov     OutMX, spi_data
:Mag_Done_X

:Mag_Read_Y
'                        test    t3, #2          wc      'Y data available?
'              if_nc     jmp     #:Mag_Done_Y                                            

                        mov     spi_reg, #$6a           'read the Magnetometer Y register ($2a | $40 = continuous read mode)              
                        call    #SPI_ReadWord
                        mov     OutMY, spi_data
:Mag_Done_Y

:Mag_Read_Z
'                        test    t3, #4          wc      'Z data available?
'              if_nc     jmp     #:Mag_Done_Z                                            

                        mov     spi_reg, #$6c           'read the Magnetometer Z register ($2c | $40 = continuous read mode)              
                        call    #SPI_ReadWord
                        mov     OutMZ, spi_data
:Mag_Done_Z

                        '---- End Magnetometer----------




                        '---- Altimeter ----------------
                        mov     spi_cs_mask, amask      'Finally, read the altimeter

'                        mov     spi_reg, #$27           'Read the Altimeter status register to see if data is ready
'                        call    #SPI_ReadByte

'                        mov     t3, spi_data            'Store to temp register t3            

'                        test    t3, #1          wc      'Temperature data available?
'        if_nc           jmp     #:SkipAltTemperature                                   

:ReadAltTemperature
                        mov     spi_reg, #$6B           'Read the temperature register (| $40 = continuous read mode
                        call    #SPI_ReadWord
                        mov     OutAltTemp, spi_data

:SkipAltTemperature
'                        test    t3, #2          wc      'Pressure data available?
'        if_nc           jmp     #:SkipAltPressure                                   


:ReadAltPressure
                        mov     spi_reg, #$28           'Read the pressure register (| $40 = continuous read mode)
                        call    #SPI_ReadByte
                        mov     OutAlt, spi_data

                        mov     spi_reg, #$29           'Read the pressure register (| $40 = continuous read mode)
                        call    #SPI_ReadByte
                        shl     spi_data, #8
                        or      OutAlt, spi_data

                        mov     spi_reg, #$2A           'Read the pressure register (| $40 = continuous read mode)
                        call    #SPI_ReadByte
                        shl     spi_data, #16
                        or      OutAlt, spi_data

:SkipAltPressure

                        call    #ComputeDrift           'Compute the temperature drift offsets
                        call    #ComputeAccelMedian     '~1400 cycles per 9 pt median, ~4200 cycles max
                        
                        subs    OutGX, DriftX
                        subs    OutGY, DriftY           'Apply the temperature drift offsets to the gyro readings
                        subs    OutGZ, DriftZ

                        
                        '---- Write Hub Outputs --------
                        mov     outAddr, par
                        movd    :OutHubAddr, #OutTemp   'Put the COG address to read from in the D field of the :OutHubAddr instruction
                        mov     t1, #12                 '12 parameters to copy from COG to HUB

:HubWriteLoop                                                        

:OutHubAddr             wrlong  0-0, outAddr            'Write the data to the HUB
                        add     :OutHubAddr, d_field    'Increment the COG source address (in the instruction above)
                        add     outAddr, #4             'Increment the HUB target address
                        
                        djnz    t1, #:HubWriteLoop      'Keep going for all 12 registers
                        

                        call    #WriteLEDs


                        sub     LoopTime, cnt
                        neg     LoopTime, LoopTime
                        add     outAddr, #4
                        wrlong  LoopTime, outAddr                                                
                        
                        
                                

                        waitcnt counter, loopdelay      'Wait for the main loop delay
                        jmp     #main_loop              'Repeat forever







''------------------------------------------------------------------------------
'' Get parameter, advance parameter pointer, result MASK in t2, VALUE in t3
''------------------------------------------------------------------------------
param                   rdlong  t3,t1                   'get parameter into t3
                        add     t1,#4                   'point to next parameter
                        mov     t2,#1                   'make pin mask in t2
                        shl     t2,t3
param_ret               ret
'------------------------------------------------------------------------------



''------------------------------------------------------------------------------
'' Configure the settings of the LSM-9DS1
''------------------------------------------------------------------------------
Config_GryoAccelMag
                        mov     spi_cs_mask, sgmask     'Set the enable pin for the gyro/accelerometer

                        'Ctrl_REG1_G (10h)
                        'Data rate, frequency select, bandwidth for gyro
                        'ODR_G[2..0]__FS_G[1..0]__0__BW_G[1..0]
                        
                        'ODR_G[2:0] := %101     'Output Data Rate = 476hz
                        'FS_G[1..0] := %11      'Full scale operation, 2000 deg/sec  (00 = 245 d/s, 11 = 2000 d/s)        
                        'BW_G[1..0] := %10      'Bandwidth cutoff = 57Hz

                        mov     spi_reg, #$10
                        mov     spi_data, #%101_11_0_10
                        call    #SPI_Write


                        'Ctrl_REG2_G (11h)
                        '0000__INT_SEL[1..0]__OUT_SEL[1..0]
                        'Interrupt Generator
                        'Output selection

                        'Ctrl_REG3_G (12h)
                        'High-pass filter enable & settings

                        'Orient_CFG_G (13h)
                        'Orientation / sign settings
                        '00__SignX_G__SignY_G__SignZ_G__Orient[2..0]                            

                        'Ctrl_REG5_XL (1fh)
                        'Decimation / enable for accelerometer
                        'DEC[1..0]__Zen_XL__Yen_XL__Xen__XL__000



                        'Ctrl_REG6_XL (20h)
                        'Data rate, frequency select, bandwidth for accelerometer
                        'ODR_XL[2..0]__FS_XL[1..0]__BW_SCAL_ODR__BW_XL[1..0]
                        
                        'ODR_XL[2..0] := %101   'Output data rate = 476hz
                        'FS_XL[1..0] := %10     'Accel scale = +/- 4g  (00=2g, 10=4g, 11=8g, 01=16g)
                        'BW_SCAL_ODR := 0       'Scale bandwidth according to sample rate = 0  (1 = use BW_XL)
                        'BW_XL[1..0] := %00     'filter bandwidth (00=408hz, 01=211hz, 10=105hz, 11=50hz), only used if BW_SCAL == 1

                        mov     spi_reg, #$20
                        mov     spi_data, #%101_10_0_00                        
                        call    #SPI_Write
                                                

                        'Remaining Gyro / Accel registers are left at startup defaults



                        'Magnetometer configuration

                        mov     spi_cs_mask, smmask     'Set the enable pin for the magnetometer

                        'Ctrl_Reg1_M (20h)
                        'TempComp___OM[1..0]__DO[2..0]__FastODR__ST
                        'TempComp := 0
                        'OM[1..0] := %11        'Ultra-high performance mode for X&Y axis
                        'DO[2..1] := %111       '80Hz output
                        'Fast_ODR := 0          'Higher than 80Hz not required        
                        'ST := 0                'Self-test disabled

                        mov     spi_reg, #$20
                        mov     spi_data, #%0_11_111_0_0                        
                        call    #SPI_Write


                        'Ctrl_Reg2_M (21h)
                        '0__FS[1..0]__0__REBOOT__SoftRST__00

                        'FS[1..0] := %01        '+/- 8 gauss
                        mov     spi_reg, #$21
                        mov     spi_data, #%0_01_0_0_0_00                        
                        call    #SPI_Write
                        

                        'Ctrl_Reg3_M (22h)
                        'I2CDisable__0__LP__00__SIM__MD[1..0]

                        'I2CDisable := 0        'Disable the I2C interface
                        'LP := 0                'Low-power mode off
                        'SIM := 1               'SPI Read/Write enable  (appears to be incorrectly documented, set to zero instead)
                        'MD[1..0] := %00        'Continuous conversion mode

                        mov     spi_reg, #$22
                        mov     spi_data, #%0_0_0_00_0_00                        
                        call    #SPI_Write
                                                                          

                        'Ctrl_Reg4_M (23h)
                        '0000__OMZ[1..0]__BLE__0

                        'OMZ[1..0] := %11       'ultra-high performance mode for Z axis
                        'BLE := 0               'LSB at low address

                        mov     spi_reg, #$23
                        mov     spi_data, #%0000_11_0_0                        
                        call    #SPI_Write


                        'Ctrl_Reg5_M (24h)
                        'FastRead__BDU_000000

                        'FastRead := 0          'Fast read disabled
                        'BDU := 1               'Block data output until MSB and LSB have been read

                        mov     spi_reg, #$24
                        mov     spi_data, #%0_1_000000                        
                        call    #SPI_Write
                                      
                                                                       

Config_GryoAccelMag_ret ret


''------------------------------------------------------------------------------
'' Configure the altimeter settings of the LPS25H
''------------------------------------------------------------------------------
Config_Altimeter
                        mov     spi_cs_mask, amask      'Set the enable pin for the altimeter

                        'CTRL_REG1 (20h)
                        'PD__ODR[2..0]__DIFF_EN__BDU__RESET_AZ__SIM

                        'PD := 1 (enable device)
                        'ODR := %100  (25hz output)
                        'DIFF_EN := 0  (differential enable off)
                        'BDU := 1  (block-data update)
                        'RESET_AZ := 0
                        'SIM := 0  (4-wire SPI mode)

                        mov     spi_reg, #$20
                        mov     spi_data, #%1_100_0_1_0_0                        
                        call    #SPI_Write



                        'CTRL_REG2 (21h)
                        'BOOT__FIFO_EN__WTM_EN__FIFO_MEAN_DEC__I2C__SWRESET__AUTO_ZERO__ONE_SHOT
                        'BOOT := 0  (normal operation)
                        'FIFO_EN := 1  (enable fifo)
                        'WTM_EN := 1  (enable watermark level use)
                        'FIFO_MEAN_DEC := 0  (1hz output data rate decimation disabled)
                        'I2C := 0  (I2C mode disabled)
                        'SWRESET := 0  (normal operation)
                        'AUTO_ZERO := 0  (auto-zero mode disabled)
                        'ONE_SHOT := 0  (continuous operation)  

                        mov     spi_reg, #$21
                        mov     spi_data, #%0_1_1_00000                        
                        call    #SPI_Write



                        'RES_CONF (0fh) - resolution configure
                        '0000__AVGP[1..0]__AVGT[1..0]                                                



                        'FIFO_CTRL (2Eh)
                        'F_MODE[2..0]__WTM_POINT[4..0]

                        'F_MODE := %110 = FIFO mean mode (running average)   (000 = bypass mode)
                        'WTM_POINT := %01111 = 16 sample moving average (%11111 = 32, %00111 = 8, %00011 = 4, %00001 = 2)                         

                        mov     spi_reg, #$2E
                        mov     spi_data, #%110_01111                        
                        call    #SPI_Write
                        

                        'Remaining registers are left at startup defaults
                                                                       

Config_Altimeter_ret    ret



''------------------------------------------------------------------------------
'' SPI ReadByte - Read a byte from a register on the gyro/accel device
''
'' spi_reg  - the register to read from
'' spi_data - the resulting 8-bit value read from the device 
''------------------------------------------------------------------------------
SPI_ReadByte
                        mov     spi_bits, spi_reg       'Copy the address value into the output bit rack
                        or      spi_bits, #$80          'Set the read bit on the output address value
                        mov     spi_bitcount, #8        '8 bits to send

                        andn    outa, spi_cs_mask       'Set CS low

                        call    #SPI_SendBits           'Send the bits currently in the spi_bits register 

                        mov     spi_data, #0            'Zero the input register
                        mov     spi_bitcount, #8        '8 bits to receive
                        
                        call    #SPI_RecvBits
                        
                        or      outa, spi_cs_mask       'Set CS high
                        
SPI_ReadByte_ret        ret



''------------------------------------------------------------------------------
'' SPI ReadWord - read a two-byte value in low-high order from a device
''
'' spi_reg  - the register of the low-byte to read.  High byte is (spi_reg+1)
'' spi_data - the resulting 16-bit value read from the device 
''------------------------------------------------------------------------------
SPI_ReadWord
                        mov     spi_bits, spi_reg       'Copy the address value into the output bit rack
                        or      spi_bits, #$80          'Set the read bit on the output address value
                        mov     spi_bitcount, #8        '8 bits to send

                        andn    outa, spi_cs_mask       'Set CS low
                        
                        call    #SPI_SendBits           'Send the bits currently in the spi_bits register 

                        mov     spi_data, #0            'Zero the input register
                        mov     spi_bitcount, #8        '8 bits to receive
                        
                        call    #SPI_RecvBits

                        'The chip will auto-increment registers, so we can just keep reading bits without telling it to stop

                        'Since the low-byte is first, rotate it around, so the register looks like this: 0_L_0_0  (each char is 8 bits)
                        ror     spi_data, #16
                        mov     spi_bitcount, #8        '8 more bits to receive

                        call    #SPI_RecvBits
                        
                        'The high byte was just read into the lowest 8-bits, so it now looks like this: L_0_0_H
                        'Rotate the bits to the left by 8, to move them like this: 0_0_H_L 
                        rol     spi_data, #8

                        or      outa, spi_cs_mask       'Set CS high
                        
                        test    spi_data, bit_15   wc   'Test the sign bit of the result
                        muxc    spi_data, sign_extend   'Replicate the sign bit to the upper-16 bits of the long


SPI_ReadWord_ret        ret



''------------------------------------------------------------------------------
'' SPI ReadTriple - read a three-byte value in low-high order from a device
''
'' spi_reg  - the register of the low-byte to read.  Highest byte is (spi_reg+2)
'' spi_data - the resulting 24-bit value read from the device 
''------------------------------------------------------------------------------
SPI_ReadTriple
                        mov     spi_bits, spi_reg       'Copy the address value into the output bit rack
                        or      spi_bits, #$80          'Set the read bit on the output address value
                        mov     spi_bitcount, #8        '8 bits to send

                        andn    outa, spi_cs_mask       'Set CS low
                        
                        call    #SPI_SendBits           'Send the bits currently in the spi_bits register 

                        mov     spi_data, #0            'Zero the input register
                        mov     spi_bitcount, #8        '8 bits to receive
                        
                        call    #SPI_RecvBits

                        'The chip will auto-increment registers, so we can just keep reading bits without telling it to stop

                        'Since the low-byte is first, rotate it around, so the register looks like this: 0_L_0_0  (each char is 8 bits)
                        ror     spi_data, #16
                        mov     spi_bitcount, #8        '8 more bits to receive

                        call    #SPI_RecvBits
                        
                        'The next byte was just read into the lowest 8-bits, so it now looks like this: L_0_0_H

                        'Rotate it around, so the register looks like this: 0_H_L_0  (each char is 8 bits)
                        ror     spi_data, #16
                        mov     spi_bitcount, #8        '8 more bits to receive (call this "Upper")

                        call    #SPI_RecvBits

                        'The upper byte was just read into the lowest 8-bits, so it now looks like this: H_L_0_U
                        'Rotate the bits to the left by 16, to move them like this: 0_U_H_L 

                        rol     spi_data, #16

                        or      outa, spi_cs_mask       'Set CS high
                        

SPI_ReadTriple_ret      ret


''------------------------------------------------------------------------------
'' SPI Write - write a value to a register on the gyro/accel device
''
'' spi_reg  - the register index to write to
'' spi_data - the value to write to that register  
''------------------------------------------------------------------------------
SPI_Write
                        mov     spi_bits, spi_reg       'Copy the address value into the output bit rack
                        andn    spi_bits, #$80          'Set the read bit on the output address value
                        shl     spi_bits, #8            'Shift the address register up 8 bits to make room for the data value

                        or      spi_bits, spi_data      'OR in the data value

'Call this entry point with 16 bits + write bit already in spi_bits
SPI_WriteFast                        
                        mov     spi_bitcount, #16       'Now have 16 bits total to write                                

                        andn    outa, spi_cs_mask       'Set CS low

                        call    #SPI_SendBits           'Send the bits in the spi_bits register
                        
                        or      outa, spi_cs_mask       'Set CS high
                                                 
SPI_WriteFast_ret
SPI_Write_ret           ret



''------------------------------------------------------------------------------
'' SPI Send Bits - shift bits OUT of spi_bits while toggling the clock
''------------------------------------------------------------------------------
SPI_SendBits
                        ror     spi_bits, spi_bitcount  'Rotate the bits around so the next bit to go out is the HIGH bit

:_loop
                        shl     spi_bits, #1    wc      'Shift the next output bit into the carry                        
                        muxc    outa, imask             'Set SDI to output bit

                        andn    outa, cmask             'Set CLK low
                        nop                             'Wait a teeny bit, just in case 

                        or      outa, cmask             'Set CLK high (device tests bit during transition)
                        nop                             'Wait a teeny bit, just in case 

                        djnz    spi_bitcount, #:_loop   'Loop for all the bits                   

SPI_SendBits_ret        ret


''------------------------------------------------------------------------------
'' SPI Read Bits - shift bits IN to spi_data while toggling the clock
''------------------------------------------------------------------------------
SPI_RecvBits

:_loop
                        andn    outa, cmask             'Set CLK low
                        nop                             'Wait a teeny bit, just in case 

                        test    omask, ina      wc      'Test input bit, sets the carry based on result
                        rcl     spi_data, #1            'Rotate the carry bit into the low bit of the output

                        or      outa, cmask             'Set CLK high
                        nop                             'Wait a teeny bit, just in case 

                        djnz    spi_bitcount, #:_loop   'Loop for all the bits

SPI_RecvBits_ret        ret




''------------------------------------------------------------------------------
'' Write RGB values out to the WS2812b LED array
''------------------------------------------------------------------------------
WriteLEDs
                        andn    outa, ledMask           'Drive the LED line low to reset
                        or      dira, ledMask           'Enable the LED pin as an output

                        mov     t3, ledCount
                        mov     t1, ledAddress               
                        
                        mov     spi_delay, cnt
                        add     spi_delay, LED_RESET    'wait for the reset time

                        waitcnt spi_delay, #0

:ledLoop

                        rdlong  spi_bits, t1            'Read the RGB triple from hub memory
                        add     t1, #4                  'Increment to the next address
                        
                        shl     spi_bits, #8            'high bit is the first one out, so shift it into position
                        mov     spi_bitcount, #24       '24 bits to send
:bitLoop
                        rcl     spi_bits, #1    wc

        if_nc           mov     spi_delay, #LED_0_HI  
        if_c            mov     spi_delay, #LED_1_HI                

                        or      outa, ledMask
                        add     spi_delay, cnt          'sync the timer to the bit-delay time
                          
        if_nc           waitcnt spi_delay, #LED_0_LO
        if_c            waitcnt spi_delay, #LED_1_LO                
         
                        andn    outa, ledMask           'pull the LED pin low             
                        waitcnt spi_delay, #0           'hold for the bit duration

                        djnz    spi_bitcount, #:bitLoop

                        djnz    t3, #:ledLoop

                        andn    dira, ledMask           'Set the LED pin as an input again (high-z / floating)
                        
WriteLEDs_ret           ret



''------------------------------------------------------------------------------
'' ComputeDrift - calculate corrected gyro values accounting for temperature drift
''------------------------------------------------------------------------------


ComputeDrift

                        mov     t3, driftHubAddr        'Pull the current drift values out of the HUB (allows for dynamic config)
                        rdlong  DriftScaleGX, t3
                        add     t3, #4   
                        rdlong  DriftScaleGY, t3   
                        add     t3, #4   
                        rdlong  DriftScaleGZ, t3   
                        add     t3, #4   
                        rdlong  DriftOffsetGX, t3   
                        add     t3, #4   
                        rdlong  DriftOffsetGY, t3   
                        add     t3, #4   
                        rdlong  DriftOffsetGZ, t3   


                        'Compute drift value for X axis                        
                        mov     divisor, DriftScaleGX
                        mov     dividend, OutTemp
                        mov     divResult, #0

                        cmp     divisor, #0     wz, wc
              if_nz     call    #Divide
                        mov     DriftX, divResult
                        add     DriftX, DriftOffsetGX                                           


                        'Compute drift value for Y axis                        
                        mov     divisor, DriftScaleGY
                        mov     dividend, OutTemp
                        mov     divResult, #0

                        cmp     divisor, #0     wz, wc
              if_nz     call    #Divide
                        mov     DriftY, divResult
                        add     DriftY, DriftOffsetGY                                           


                        'Compute drift value for Z axis                        
                        mov     divisor, DriftScaleGZ
                        mov     dividend, OutTemp
                        mov     divResult, #0

                        cmp     divisor, #0     wz, wc
              if_nz     call    #Divide
                        mov     DriftZ, divResult
                        add     DriftZ, DriftOffsetGZ                                           
                        
                        
ComputeDrift_Ret        ret



''------------------------------------------------------------------------------
''------------------------------------------------------------------------------
Divide
                        mov     signbit, dividend
                        xor     signbit, divisor        'Figure out the sign of the result
                        shr     signbit, #31

                        
                        abs     dividend, dividend
                        abs     divisor, divisor

                        mov     divCounter, #20         ' This ONLY works for divisions of up to 1024
                        shl     divisor, divCounter
                        mov     resultShifted, #1
                        shl     resultShifted, divCounter

                        add     divCounter, #1
                        mov     divResult, #0

:divLoop                        
                        cmp     dividend, divisor   wc
              if_nc     add     divResult, resultShifted
              if_nc     sub     dividend, divisor
                        shr     resultShifted, #1
                        shr     divisor, #1     
                        djnz    divCounter, #:divLoop

                        cmp     signbit, #0     wc, wz
                        negnz   divResult, divResult

Divide_Ret              ret



'------------------------------------------------------------------------------
ComputeAccelMedian
                        'Add the x, y, and z values to the running tables
                        mov     t1, AccelTableIndex
                        add     t1, #AccelXTable
                        movd    :XDest, t1
                        mov     t1, AccelTableIndex
          :XDest        mov     0-0, OutAX 

                        add     t1, #AccelYTable
                        movd    :YDest, t1
                        mov     t1, AccelTableIndex
          :YDest        mov     0-0, OutAY
           
                        add     t1, #AccelZTable
                        movd    :ZDest, t1
                        add     AccelTableIndex, #1
          :ZDest        mov     0-0, OutAZ 

                        cmp     AccelTableIndex, #9     wz
              if_z      mov     AccelTableIndex, #0


                        'Select the middle value from each of the running lists
                        mov     SrcAddr, #AccelXTable
                        call    #SelectTableMedian
                        mov     OutAX, Smallest                        

                        mov     SrcAddr, #AccelYTable
                        call    #SelectTableMedian
                        mov     OutAY, Smallest                        

                        mov     SrcAddr, #AccelZTable
                        call    #SelectTableMedian
                        mov     OutAZ, Smallest                        


ComputeAccelMedian_Ret
                        ret


'------------------------------------------------------------------------------
SelectTableMedian

' Find the median value in a list of 9 signed values
' Go through the list (N+1)/2 times (5 iterations for a 9-entry list)
' In each iteration, choose the smallest value that hasn't already been chosen
' It's basically half a bubble sort

                        mov     UsedMask, #0
                        'Iterate the list 5 times (outer loop)
                        mov     t3, #5

  :Outer
                        mov     Smallest, #1
                        shl     Smallest, #30   'Big number to start with                      

                        'Iterate all 9 entries
                        mov     t2, #9
                        mov     t1, #1
                        movs    :TestAddr, SrcAddr      'Write the address of the start of the table to test
  :Inner                        
                        
                        'If this entry is not masked
                        test    UsedMask, t1            wz
              if_nz     jmp     #:SkipEntry
                        
                        'If this table entry is smaller than the smallest chosen
        :TestAddr       maxs    Smallest, 0-0           wz, wc
        if_nc_or_z      mov     SmallIndex, t1

  :SkipEntry
                        shl     t1, #1
                        add     :TestAddr, #1           'Increment the source address we're testing
                        djnz    t2, #:Inner 

                        or      UsedMask, SmallIndex    'Mark the smallest entry this loop as used
                        djnz    t3, #:Outer                        
                        
SelectTableMedian_Ret
                        ret


'
' Initialized data
'
loopDelay               long    _clkfreq / 500          'Main loop at 500 hz
d_field                 long    $200

bit_15                  long    $8000                   'Sign bit of a 16-bit value
sign_extend             long    $FFFF_0000              'Bits to mask in for 16 to 32 bit sign extension

LED_RESET               long    6000 'minimum of 50 * ONE_uS


DriftScaleGX            long    0               '9                
DriftScaleGY            long    0               '2                
DriftScaleGZ            long    0               '-20
                
DriftOffsetGX           long    0               '64
DriftOffsetGY           long    0               '445
DriftOffsetGZ           long    0               '29


AccelTableIndex         long    0                       'Index into the accel values median table
AccelXTable             long    0,0,0,0,0,0,0,0,0       '9 entries per accel table
AccelYTable             long    0,0,0,0,0,0,0,0,0
AccelZTable             long    0,0,0,0,0,0,0,0,0
 
'
' Uninitialized data

spi_reg                 res     1                       'SPI register to read
spi_data                res     1                       'SPI value to output, or result from a read

spi_bits                res     1                       'SPI bits to output in SPI_SendBits function
spi_bitcount            res     1                       'Number of bits to send / receive
spi_delay               res     1                       'Next counter value to wait for when sending / receiving
spi_cs_mask             res     1                       'Set prior to read - The CS pin mask to enable

t1                      res     1                       '
t2                      res     1                       'internal temporary registers
t3                      res     1                       '

omask                   res     1                       'Device output pin mask (Prop input)
imask                   res     1                       'Device input pin mask (Prop output) 
cmask                   res     1                       'Clock pin mask
sgmask                  res     1                       'Select Gyro pin mask
smmask                  res     1                       'Select Magnetometer pin mask
amask                   res     1                       'Select Altimeter pin mask

ledmask                 res     1                       'LED pin mask
ledAddress              res     1                       'HUB Address of LED values
ledCount                res     1

outAddr                 res     1                       'Output hub address        

counter                 res     1                       'Master loop time counter
driftHubAddr            res     1                       'Hub address of the drift values (for dynamic configuration)
dividend                res     1
divisor                 res     1
divResult               res     1
resultShifted           res     1
signbit                 res     1
divCounter              res     1

SrcAddr                 res     1
Smallest                res     1
SmallIndex              res     1                       'Used by the Accelerometer Median computation        
UsedMask                res     1

DriftX                  res     1
DriftY                  res     1
DriftZ                  res     1

OutTemp                 res     1
OutGX                   res     1
OutGY                   res     1
OutGZ                   res     1

OutAX                   res     1
OutAY                   res     1
OutAZ                   res     1

OutMX                   res     1
OutMY                   res     1
OutMZ                   res     1

OutAlt                  res     1
OutAltTemp              res     1

LoopTime                res     1                       'Register used to measure how much time a single loop actually takes

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}