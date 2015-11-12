//
// Prefs - User prefs storage for Elev8-FC
//

#include <string.h>   // for memset()
#include <fdserial.h>

#include "eeprom.h"
#include "prefs.h"


PREFS Prefs;


void Prefs_Load(void)
{
  EEPROM::ToRam( &Prefs, (char *)&Prefs + sizeof(Prefs)-1, 32768 );    //Copy from EEPROM to DAT, address 32768

  int testChecksum = Prefs_CalculateChecksum();
  if( testChecksum != Prefs.Checksum )
  {
    Prefs_SetDefaults();
    Prefs_Save();
  }
}

void Prefs_Save(void)
{
  Prefs.Checksum = Prefs_CalculateChecksum();
  EEPROM::FromRam( &Prefs, (char *)&Prefs + sizeof(Prefs)-1, 32768 );  //Copy from DAT to EEPROM, address 32768
}


void Prefs_SetDefaults(void)
{
  memset( &Prefs, 0, sizeof(Prefs) );

  Prefs.SBUSCenter = 1000;
  Prefs.UseBattMon = 1;

  Prefs.RollCorrect[0] = 0.0f;                         //Sin of roll correction angle
  Prefs.RollCorrect[1] = 1.0f;                         //Cos of roll correction angle

  Prefs.PitchCorrect[0] = 0.0f;                        //Sin of pitch correction angle 
  Prefs.PitchCorrect[1] = 1.0f;                        //Cos of pitch correction angle 

  // MagOffsetX=0, MagScaleX=1, MagOffsetY=2, MagScaleY=3, MagOffsetZ=4, MagScaleZ=5;
  Prefs.MagScaleOfs[1] = 1024;
  Prefs.MagScaleOfs[3] = 1024;
  Prefs.MagScaleOfs[5] = 1024;

  Prefs.MinThrottle = 8500;   //8000 = 1ms in 1/8th uS steps = "full" throttle range is 1ms to 2ms

  Prefs.ThroChannel = 0;      //Standard radio channel mappings
  Prefs.AileChannel = 1;
  Prefs.ElevChannel = 2;
  Prefs.RuddChannel = 3;
  Prefs.GearChannel = 4;
  Prefs.Aux1Channel = 5;
  Prefs.Aux2Channel = 6;
  Prefs.Aux3Channel = 7;
}


int Prefs_CalculateChecksum(void)
{
  unsigned int r = 0x55555555;            //Start with a strange, known value
  for( int i=0; i < (sizeof(Prefs)/4)-1; i++ )
  {
    r = (r << 7) | (r >> (32-7));
    r = r ^ ((unsigned int*)&Prefs)[i];     //Jumble the bits, XOR in the prefs value
  }    
  return (int)r;
}


extern fdserial * dbg;

static int tGetC( void ) {
  return fdserial_rxChar( dbg );
}

static void tPutC( char c ) {
  fdserial_txChar( dbg, c );
}

static void tPutHexNibble( int x ) {
  if( x <= 9 ) {
    tPutC( x + '0' );
  }
  else {
    tPutC( x - 10 + 'a' );
  }        
}  

static void tPutHex( int x, int len ) {
  for( int i=len-1; i>=0; i-- ) {
    tPutHexNibble( (x>>(4*i)) & 15 );
  }    
}


void Prefs_Test( void )
{
  // This function exists only to test and validate the Load / Save / Checksum code
   
  tGetC();

  EEPROM::ToRam( &Prefs, (char *)&Prefs + sizeof(Prefs)-1, 32768 );    //Copy from EEPROM to DAT, address 32768

  int testCheck = Prefs_CalculateChecksum();
  tPutC(0);
  tPutHex( Prefs.Checksum, 8 );
  tPutC(32);
  tPutHex( testCheck, 8 );
  tPutC(13);

  //EEPROM::FromRam( &Prefs, (char *)&Prefs + sizeof(Prefs)-1, 32768 );    //Copy from EEPROM to DAT, address 32768

  //tPutHex( Prefs.Checksum, 8 );
  //tPutC(32);
  //tPutHex( testCheck, 8 );
  //tPutC(13);
  //tPutC(13);


  Prefs_SetDefaults();
  testCheck = Prefs_CalculateChecksum();
  tPutHex( testCheck, 8 );
  tPutC(13);

  Prefs_Save();

  EEPROM::ToRam( &Prefs, (char *)&Prefs + sizeof(Prefs)-1, 32768 );    //Copy from EEPROM to DAT, address 32768

  testCheck = Prefs_CalculateChecksum();

  tPutHex( Prefs.Checksum, 8 );
  tPutC(32);
  tPutHex( testCheck, 8 );
  tPutC(13);

  tGetC();
}