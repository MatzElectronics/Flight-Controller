
#ifndef __BEEP_H__
#define __BEEP_H__


void BeepHz( int Hz , int Delay );
void BeepTune(void);

void Beep(void);
void Beep2(void);
void Beep3(void);

void BeepOn(int CtrAB, int Pin, int Freq);
void BeepOff(int CtrAB);

#endif
