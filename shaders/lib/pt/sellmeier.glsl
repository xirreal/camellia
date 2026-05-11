// 7-bin spectral dispersion for glass refraction.
// Column-normalised RGB masks (Σ MASK[i] = (1,1,1)) so the throughput stays
// unbiased with uniform 1/N selection. IOR is computed at runtime via the
// Sellmeier equation for BK7 crown glass (see sellmeierIOR below).
// Wavelengths (nm):  425  465  490  535  575  605  645
// Column sums for the 7-mask palette: R=3, G=4, B=3 → entries divided accordingly.
const int GLASS_BIN_COUNT = 7;
const float GLASS_WL_BIN[7] = float[7](
      425.0, // V
      465.0, // B
      490.0, // C
      535.0, // G
      575.0, // Y
      605.0, // O
      645.0 // R
   );
const vec3 GLASS_MASK_BIN[7] = vec3[7](
      vec3(0.0, 0.0, 1.0 / 3.0), // V → (0,0,1)
      vec3(0.0, 0.0, 1.0 / 3.0), // B → (0,0,1)
      vec3(0.0, 1.0 / 4.0, 1.0 / 3.0), // C → (0,1,1)
      vec3(0.0, 1.0 / 4.0, 0.0), // G → (0,1,0)
      vec3(1.0 / 3.0, 1.0 / 4.0, 0.0), // Y → (1,1,0)
      vec3(1.0 / 3.0, 1.0 / 4.0, 0.0), // O → (1,1,0)
      vec3(1.0 / 3.0, 0.0, 0.0) // R → (1,0,0)
   );

float sellmeierIOR(float lambda_nm, vec3 B, vec3 C) {
   float L = lambda_nm * 1e-3;
   float L2 = L * L;
   vec3 terms = B * L2 / (vec3(L2) - C);
   return sqrt(1.0 + terms.x + terms.y + terms.z);
}

void glassCoeffs_FK5HTi(out vec3 B, out vec3 C) {
   B = vec3(0.90936218, 0.279077054, 0.891813298);
   C = vec3(0.005201425, 0.0158938446, 95.9109448);
}
void glassCoeffs_N_FK5(out vec3 B, out vec3 C) {
   B = vec3(0.844309338, 0.344147824, 0.910790213);
   C = vec3(0.00475112, 0.0149814849, 97.8600293);
}
void glassCoeffs_N_FK51A(out vec3 B, out vec3 C) {
   B = vec3(0.971247817, 0.216901417, 0.904651666);
   C = vec3(0.00472302, 0.0153575612, 168.68133);
}
void glassCoeffs_N_FK58(out vec3 B, out vec3 C) {
   B = vec3(0.738042712, 0.363371967, 0.989296264);
   C = vec3(0.003390656, 0.0117551189, 212.842145);
}
void glassCoeffs_N_PK51(out vec3 B, out vec3 C) {
   B = vec3(1.15610775, 0.153229344, 0.785618966);
   C = vec3(0.005855974, 0.0194072416, 140.537046);
}
void glassCoeffs_N_PK52A(out vec3 B, out vec3 C) {
   B = vec3(1.029607, 0.1880506, 0.736488165);
   C = vec3(0.005168002, 0.0166658798, 138.964129);
}
void glassCoeffs_N_PSK3(out vec3 B, out vec3 C) {
   B = vec3(0.88727211, 0.489592425, 1.04865296);
   C = vec3(0.004698241, 0.0161818463, 104.374975);
}
void glassCoeffs_N_PSK53A(out vec3 B, out vec3 C) {
   B = vec3(1.38121836, 0.196745645, 0.886089205);
   C = vec3(0.007064163, 0.0233251345, 97.4847345);
}
void glassCoeffs_N_BK7(out vec3 B, out vec3 C) {
   B = vec3(1.03961212, 0.231792344, 1.01046945);
   C = vec3(0.006000699, 0.0200179144, 103.560653);
}
void glassCoeffs_N_BK7HT(out vec3 B, out vec3 C) {
   B = vec3(1.03961212, 0.231792344, 1.01046945);
   C = vec3(0.006000699, 0.0200179144, 103.560653);
}
void glassCoeffs_N_BK7HTi(out vec3 B, out vec3 C) {
   B = vec3(1.03961212, 0.231792344, 1.01046945);
   C = vec3(0.006000699, 0.0200179144, 103.560653);
}
void glassCoeffs_N_BK7HTSultra(out vec3 B, out vec3 C) {
   B = vec3(1.03961212, 0.231792344, 1.01046945);
   C = vec3(0.006000699, 0.0200179144, 103.560653);
}
void glassCoeffs_N_BK10(out vec3 B, out vec3 C) {
   B = vec3(0.888308131, 0.328964475, 0.984610769);
   C = vec3(0.005169008, 0.0161190045, 99.7575331);
}
void glassCoeffs_P_BK7(out vec3 B, out vec3 C) {
   B = vec3(1.18318503, 0.087175643, 1.03133701);
   C = vec3(0.00722142, 0.0268216805, 101.702362);
}
void glassCoeffs_K7(out vec3 B, out vec3 C) {
   B = vec3(1.1273555, 0.124412303, 0.827100531);
   C = vec3(0.007203417, 0.0269835916, 100.384588);
}
void glassCoeffs_K10(out vec3 B, out vec3 C) {
   B = vec3(1.15687082, 0.064262544, 0.872376139);
   C = vec3(0.008094243, 0.0386051284, 104.74773);
}
void glassCoeffs_N_K5(out vec3 B, out vec3 C) {
   B = vec3(1.08511833, 0.199562005, 0.930511663);
   C = vec3(0.006610995, 0.024110866, 111.982777);
}
void glassCoeffs_N_ZK7(out vec3 B, out vec3 C) {
   B = vec3(1.07715032, 0.168079109, 0.851889892);
   C = vec3(0.006766017, 0.0230642817, 89.0498778);
}
void glassCoeffs_N_ZK7A(out vec3 B, out vec3 C) {
   B = vec3(1.07509891, 0.168895044, 0.860503983);
   C = vec3(0.006766017, 0.0230642817, 89.0498778);
}
void glassCoeffs_N_BAK1(out vec3 B, out vec3 C) {
   B = vec3(1.12365662, 0.309276848, 0.881511957);
   C = vec3(0.006447428, 0.0222284402, 107.297751);
}
void glassCoeffs_N_BAK2(out vec3 B, out vec3 C) {
   B = vec3(1.01662154, 0.319903051, 0.937232995);
   C = vec3(0.005923838, 0.0203828415, 113.118417);
}
void glassCoeffs_N_BAK4(out vec3 B, out vec3 C) {
   B = vec3(1.28834642, 0.132817724, 0.945395373);
   C = vec3(0.007799806, 0.0315631177, 105.965875);
}
void glassCoeffs_N_BAK4HT(out vec3 B, out vec3 C) {
   B = vec3(1.28834642, 0.132817724, 0.945395373);
   C = vec3(0.007799806, 0.0315631177, 105.965875);
}
void glassCoeffs_N_BAF4(out vec3 B, out vec3 C) {
   B = vec3(1.42056328, 0.102721269, 1.14380976);
   C = vec3(0.009420154, 0.0531087291, 110.278856);
}
void glassCoeffs_N_BAF10(out vec3 B, out vec3 C) {
   B = vec3(1.5851495, 0.143559385, 1.08521269);
   C = vec3(0.009266813, 0.0424489805, 105.613573);
}
void glassCoeffs_N_BAF51(out vec3 B, out vec3 C) {
   B = vec3(1.51503623, 0.153621958, 1.15427909);
   C = vec3(0.009427347, 0.04308265, 124.889868);
}
void glassCoeffs_N_BAF52(out vec3 B, out vec3 C) {
   B = vec3(1.43903433, 0.096704605, 1.09875818);
   C = vec3(0.009078001, 0.050821208, 105.691856);
}
void glassCoeffs_N_BALF4(out vec3 B, out vec3 C) {
   B = vec3(1.31004128, 0.142038259, 0.964929351);
   C = vec3(0.007965965, 0.0330672072, 109.19732);
}
void glassCoeffs_N_BALF5(out vec3 B, out vec3 C) {
   B = vec3(1.28385965, 0.071930094, 1.05048927);
   C = vec3(0.00825816, 0.0441920027, 107.097324);
}
void glassCoeffs_N_SK2(out vec3 B, out vec3 C) {
   B = vec3(1.28189012, 0.257738258, 0.96818604);
   C = vec3(0.007271916, 0.0242823527, 110.377773);
}
void glassCoeffs_N_SK2HT(out vec3 B, out vec3 C) {
   B = vec3(1.28189012, 0.257738258, 0.96818604);
   C = vec3(0.007271916, 0.0242823527, 110.377773);
}
void glassCoeffs_N_SK4(out vec3 B, out vec3 C) {
   B = vec3(1.32993741, 0.228542996, 0.988465211);
   C = vec3(0.007168741, 0.0246455892, 100.886364);
}
void glassCoeffs_N_SK5(out vec3 B, out vec3 C) {
   B = vec3(0.991463823, 0.495982121, 0.987393925);
   C = vec3(0.005227305, 0.0172733646, 98.3594579);
}
void glassCoeffs_N_SK5HTi(out vec3 B, out vec3 C) {
   B = vec3(0.991463823, 0.495982121, 0.987393925);
   C = vec3(0.005227305, 0.0172733646, 98.3594579);
}
void glassCoeffs_N_SK11(out vec3 B, out vec3 C) {
   B = vec3(1.17963631, 0.229817295, 0.935789652);
   C = vec3(0.006802821, 0.0219737205, 101.513232);
}
void glassCoeffs_N_SK14(out vec3 B, out vec3 C) {
   B = vec3(0.936155374, 0.594052018, 1.04374583);
   C = vec3(0.004617165, 0.016885927, 103.736265);
}
void glassCoeffs_N_SK16(out vec3 B, out vec3 C) {
   B = vec3(1.34317774, 0.241144399, 0.994317969);
   C = vec3(0.007046873, 0.0229005, 92.7508526);
}
void glassCoeffs_P_SK57(out vec3 B, out vec3 C) {
   B = vec3(1.31053414, 0.169376189, 1.10987714);
   C = vec3(0.007408772, 0.0254563489, 107.751087);
}
void glassCoeffs_P_SK57Q1(out vec3 B, out vec3 C) {
   B = vec3(1.30536483, 0.171434328, 1.10117219);
   C = vec3(0.007364088, 0.0255786047, 106.72606);
}
void glassCoeffs_P_SK58A(out vec3 B, out vec3 C) {
   B = vec3(1.3167841, 0.171154756, 1.12501473);
   C = vec3(0.007207175, 0.0245659595, 102.739728);
}
void glassCoeffs_P_SK60(out vec3 B, out vec3 C) {
   B = vec3(1.40790442, 0.143381417, 1.16513947);
   C = vec3(0.007843824, 0.0287769365, 105.373397);
}
void glassCoeffs_N_KF9(out vec3 B, out vec3 C) {
   B = vec3(1.19286778, 0.089334657, 0.920819805);
   C = vec3(0.008391547, 0.0404010786, 112.572446);
}
void glassCoeffs_N_SSK2(out vec3 B, out vec3 C) {
   B = vec3(1.4306027, 0.153150554, 1.01390904);
   C = vec3(0.00823983, 0.0333736841, 106.870822);
}
void glassCoeffs_N_SSK5(out vec3 B, out vec3 C) {
   B = vec3(1.59222659, 0.103520774, 1.05174016);
   C = vec3(0.009202846, 0.0423530072, 106.927374);
}
void glassCoeffs_N_SSK8(out vec3 B, out vec3 C) {
   B = vec3(1.44857867, 0.117965926, 1.06937528);
   C = vec3(0.008693101, 0.0421566593, 111.300666);
}
void glassCoeffs_N_SSK20(out vec3 B, out vec3 C) {
   B = vec3(1.18391813, 0.406466985, 1.10391305);
   C = vec3(0.006876366, 0.024671252, 132.063408);
}
void glassCoeffs_N_LAK7(out vec3 B, out vec3 C) {
   B = vec3(1.23679889, 0.445051837, 1.01745888);
   C = vec3(0.006101055, 0.0201388334, 90.638038);
}
void glassCoeffs_N_LAK8(out vec3 B, out vec3 C) {
   B = vec3(1.33183167, 0.546623206, 1.19084015);
   C = vec3(0.006200239, 0.0216465439, 82.5827736);
}
void glassCoeffs_N_LAK9(out vec3 B, out vec3 C) {
   B = vec3(1.46231905, 0.344399589, 1.15508372);
   C = vec3(0.007242702, 0.0243353131, 85.4686868);
}
void glassCoeffs_N_LAK10(out vec3 B, out vec3 C) {
   B = vec3(1.72878017, 0.169257825, 1.19386956);
   C = vec3(0.008860146, 0.0363416509, 82.9009069);
}
void glassCoeffs_N_LAK12(out vec3 B, out vec3 C) {
   B = vec3(1.17365704, 0.588992398, 0.978014394);
   C = vec3(0.005770318, 0.0200401678, 95.4873482);
}
void glassCoeffs_N_LAK14(out vec3 B, out vec3 C) {
   B = vec3(1.50781212, 0.318866829, 1.14287213);
   C = vec3(0.007460987, 0.0242024834, 80.9565165);
}
void glassCoeffs_N_LAK21(out vec3 B, out vec3 C) {
   B = vec3(1.22718116, 0.420783743, 1.01284843);
   C = vec3(0.006020757, 0.0196862889, 88.4370099);
}
void glassCoeffs_N_LAK22(out vec3 B, out vec3 C) {
   B = vec3(1.14229781, 0.535138441, 1.04088385);
   C = vec3(0.005857786, 0.0198546147, 100.834017);
}
void glassCoeffs_N_LAK28(out vec3 B, out vec3 C) {
   B = vec3(1.50441986, 0.474120561, 1.17784354);
   C = vec3(0.007196656, 0.0249143227, 83.144321);
}
void glassCoeffs_N_LAK33B(out vec3 B, out vec3 C) {
   B = vec3(1.42288601, 0.593661336, 1.1613526);
   C = vec3(0.006702835, 0.021941621, 80.7407701);
}
void glassCoeffs_N_LAK34(out vec3 B, out vec3 C) {
   B = vec3(1.26661442, 0.665919318, 1.1249612);
   C = vec3(0.005892781, 0.0197509041, 78.8894174);
}
void glassCoeffs_P_LAK35(out vec3 B, out vec3 C) {
   B = vec3(1.3932426, 0.418882766, 1.043807);
   C = vec3(0.007159597, 0.0233637446, 88.3284426);
}
void glassCoeffs_LLF1(out vec3 B, out vec3 C) {
   B = vec3(1.21640125, 0.13366454, 0.883399468);
   C = vec3(0.008578072, 0.0420143003, 107.59306);
}
void glassCoeffs_LLF1HTi(out vec3 B, out vec3 C) {
   B = vec3(1.22510445, 0.125155671, 0.892236751);
   C = vec3(0.008704321, 0.0427325235, 108.049968);
}
void glassCoeffs_LF5(out vec3 B, out vec3 C) {
   B = vec3(1.28035628, 0.163505973, 0.893930112);
   C = vec3(0.009298544, 0.0449135769, 110.493685);
}
void glassCoeffs_LF5HTi(out vec3 B, out vec3 C) {
   B = vec3(1.28552924, 0.158357622, 0.892175122);
   C = vec3(0.009398863, 0.0452566659, 110.544829);
}
void glassCoeffs_N_F2(out vec3 B, out vec3 C) {
   B = vec3(1.39757037, 0.159201403, 1.2686543);
   C = vec3(0.009959061, 0.0546931752, 119.248346);
}
void glassCoeffs_F2HT(out vec3 B, out vec3 C) {
   B = vec3(1.34533359, 0.209073176, 0.937357162);
   C = vec3(0.009977439, 0.0470450767, 111.886764);
}
void glassCoeffs_F2HTi(out vec3 B, out vec3 C) {
   B = vec3(1.34533359, 0.209073176, 0.937357162);
   C = vec3(0.009977439, 0.0470450767, 111.886764);
}
void glassCoeffs_F5(out vec3 B, out vec3 C) {
   B = vec3(1.3104463, 0.19603426, 0.96612977);
   C = vec3(0.00958633, 0.0457627627, 115.011883);
}
void glassCoeffs_N_BASF2(out vec3 B, out vec3 C) {
   B = vec3(1.53652081, 0.156971102, 1.30196815);
   C = vec3(0.010843573, 0.0562278762, 131.3397);
}
void glassCoeffs_N_BASF64(out vec3 B, out vec3 C) {
   B = vec3(1.65554268, 0.17131977, 1.33664448);
   C = vec3(0.010448564, 0.0499394756, 118.961472);
}
void glassCoeffs_N_LAF2(out vec3 B, out vec3 C) {
   B = vec3(1.80984227, 0.15729555, 1.0930037);
   C = vec3(0.010171162, 0.0442431765, 100.687748);
}
void glassCoeffs_N_LAF7(out vec3 B, out vec3 C) {
   B = vec3(1.74028764, 0.226710554, 1.32525548);
   C = vec3(0.010792558, 0.0538626639, 106.268665);
}
void glassCoeffs_N_LAF21(out vec3 B, out vec3 C) {
   B = vec3(1.87134529, 0.25078301, 1.22048639);
   C = vec3(0.009333223, 0.0345637762, 83.2404866);
}
void glassCoeffs_N_LAF33(out vec3 B, out vec3 C) {
   B = vec3(1.79653417, 0.311577903, 1.15981863);
   C = vec3(0.009273135, 0.0358201181, 87.3448712);
}
void glassCoeffs_N_LAF34(out vec3 B, out vec3 C) {
   B = vec3(1.75836958, 0.313537785, 1.18925231);
   C = vec3(0.0087281, 0.0293020832, 85.1780644);
}
void glassCoeffs_P_LAF37(out vec3 B, out vec3 C) {
   B = vec3(1.76003244, 0.248286745, 1.15935122);
   C = vec3(0.009380064, 0.0360537464, 86.4324693);
}
void glassCoeffs_LASF35(out vec3 B, out vec3 C) {
   B = vec3(2.45505861, 0.453006077, 2.3851308);
   C = vec3(0.01356704, 0.054580302, 167.904715);
}
void glassCoeffs_N_LASF9(out vec3 B, out vec3 C) {
   B = vec3(2.00029547, 0.298926886, 1.80691843);
   C = vec3(0.012142602, 0.0538736236, 156.530829);
}
void glassCoeffs_N_LASF9HT(out vec3 B, out vec3 C) {
   B = vec3(2.00029547, 0.298926886, 1.80691843);
   C = vec3(0.012142602, 0.0538736236, 156.530829);
}
void glassCoeffs_N_LASF31A(out vec3 B, out vec3 C) {
   B = vec3(1.96485075, 0.475231259, 1.48360109);
   C = vec3(0.009820602, 0.0344713438, 110.739863);
}
void glassCoeffs_N_LASF40(out vec3 B, out vec3 C) {
   B = vec3(1.98550331, 0.274057042, 1.28945661);
   C = vec3(0.010958331, 0.0474551603, 96.9085286);
}
void glassCoeffs_N_LASF41(out vec3 B, out vec3 C) {
   B = vec3(1.86348331, 0.413307255, 1.35784815);
   C = vec3(0.009103682, 0.0339247268, 93.3580595);
}
void glassCoeffs_N_LASF43(out vec3 B, out vec3 C) {
   B = vec3(1.93502827, 0.23662935, 1.26291344);
   C = vec3(0.010400141, 0.0447505292, 87.437569);
}
void glassCoeffs_N_LASF44(out vec3 B, out vec3 C) {
   B = vec3(1.78897105, 0.38675867, 1.30506243);
   C = vec3(0.008725063, 0.0308085023, 92.7743824);
}
void glassCoeffs_N_LASF45(out vec3 B, out vec3 C) {
   B = vec3(1.87140198, 0.267777879, 1.73030008);
   C = vec3(0.011217192, 0.0505134972, 147.106505);
}
void glassCoeffs_N_LASF45HT(out vec3 B, out vec3 C) {
   B = vec3(1.87140198, 0.267777879, 1.73030008);
   C = vec3(0.011217192, 0.0505134972, 147.106505);
}
void glassCoeffs_N_LASF46A(out vec3 B, out vec3 C) {
   B = vec3(2.16701566, 0.319812761, 1.66004486);
   C = vec3(0.012359552, 0.0560610282, 107.047718);
}
void glassCoeffs_N_LASF46B(out vec3 B, out vec3 C) {
   B = vec3(2.17988922, 0.306495184, 1.56882437);
   C = vec3(0.012580538, 0.0567191367, 105.316538);
}
void glassCoeffs_N_LASF55(out vec3 B, out vec3 C) {
   B = vec3(2.30861228, 0.354736638, 1.92227125);
   C = vec3(0.0130447, 0.0557524221, 133.196869);
}
void glassCoeffs_P_LASF47(out vec3 B, out vec3 C) {
   B = vec3(1.85543101, 0.315854649, 1.28561839);
   C = vec3(0.01003282, 0.0387095168, 94.5421507);
}
void glassCoeffs_P_LASF50(out vec3 B, out vec3 C) {
   B = vec3(1.84910553, 0.329828674, 1.30400901);
   C = vec3(0.009992348, 0.0387437988, 95.8967681);
}
void glassCoeffs_P_LASF51(out vec3 B, out vec3 C) {
   B = vec3(1.84568806, 0.3390016, 1.32418921);
   C = vec3(0.009884956, 0.0378097402, 97.841543);
}
void glassCoeffs_N_SF1(out vec3 B, out vec3 C) {
   B = vec3(1.60865158, 0.237725916, 1.51530653);
   C = vec3(0.011965488, 0.0590589722, 135.521676);
}
void glassCoeffs_N_SF2(out vec3 B, out vec3 C) {
   B = vec3(1.47343127, 0.163681849, 1.36920899);
   C = vec3(0.01090191, 0.0585683687, 127.404933);
}
void glassCoeffs_N_SF4(out vec3 B, out vec3 C) {
   B = vec3(1.67780282, 0.282849893, 1.63539276);
   C = vec3(0.012679345, 0.0602038419, 145.760496);
}
void glassCoeffs_N_SF5(out vec3 B, out vec3 C) {
   B = vec3(1.52481889, 0.187085527, 1.42729015);
   C = vec3(0.011254756, 0.0588995392, 129.141675);
}
void glassCoeffs_N_SF6(out vec3 B, out vec3 C) {
   B = vec3(1.77931763, 0.338149866, 2.08734474);
   C = vec3(0.013371418, 0.0617533621, 174.01759);
}
void glassCoeffs_N_SF6HT(out vec3 B, out vec3 C) {
   B = vec3(1.77931763, 0.338149866, 2.08734474);
   C = vec3(0.013371418, 0.0617533621, 174.01759);
}
void glassCoeffs_N_SF6HTultra(out vec3 B, out vec3 C) {
   B = vec3(1.77931763, 0.338149866, 2.08734474);
   C = vec3(0.013371418, 0.0617533621, 174.01759);
}
void glassCoeffs_N_SF8(out vec3 B, out vec3 C) {
   B = vec3(1.55075812, 0.209816918, 1.46205491);
   C = vec3(0.011433834, 0.0582725652, 133.24165);
}
void glassCoeffs_N_SF10(out vec3 B, out vec3 C) {
   B = vec3(1.62153902, 0.256287842, 1.64447552);
   C = vec3(0.012224146, 0.0595736775, 147.468793);
}
void glassCoeffs_N_SF11(out vec3 B, out vec3 C) {
   B = vec3(1.73759695, 0.313747346, 1.89878101);
   C = vec3(0.013188707, 0.0623068142, 155.23629);
}
void glassCoeffs_N_SF14(out vec3 B, out vec3 C) {
   B = vec3(1.69022361, 0.288870052, 1.7045187);
   C = vec3(0.013051211, 0.061369188, 149.517689);
}
void glassCoeffs_N_SF15(out vec3 B, out vec3 C) {
   B = vec3(1.57055634, 0.218987094, 1.50824017);
   C = vec3(0.011650701, 0.0597856897, 132.709339);
}
void glassCoeffs_N_SF57(out vec3 B, out vec3 C) {
   B = vec3(1.87543831, 0.37375749, 2.30001797);
   C = vec3(0.014174952, 0.0640509927, 177.389795);
}
void glassCoeffs_N_SF57HT(out vec3 B, out vec3 C) {
   B = vec3(1.87543831, 0.37375749, 2.30001797);
   C = vec3(0.014174952, 0.0640509927, 177.389795);
}
void glassCoeffs_N_SF57HTultra(out vec3 B, out vec3 C) {
   B = vec3(1.87543831, 0.37375749, 2.30001797);
   C = vec3(0.014174952, 0.0640509927, 177.389795);
}
void glassCoeffs_N_SF66(out vec3 B, out vec3 C) {
   B = vec3(2.0245976, 0.470187196, 2.59970433);
   C = vec3(0.014705323, 0.0692998276, 161.817601);
}
void glassCoeffs_P_SF8(out vec3 B, out vec3 C) {
   B = vec3(1.55370411, 0.206332561, 1.39708831);
   C = vec3(0.011658267, 0.0582087757, 130.748028);
}
void glassCoeffs_P_SF68(out vec3 B, out vec3 C) {
   B = vec3(2.3330067, 0.452961396, 1.25172339);
   C = vec3(0.016883842, 0.0716086325, 118.707479);
}
void glassCoeffs_P_SF69(out vec3 B, out vec3 C) {
   B = vec3(1.62594647, 0.235927609, 1.67434623);
   C = vec3(0.012169668, 0.0600710405, 145.651908);
}
void glassCoeffs_SF1(out vec3 B, out vec3 C) {
   B = vec3(1.55912923, 0.284246288, 0.968842926);
   C = vec3(0.0121481, 0.0534549042, 112.174809);
}
void glassCoeffs_SF2(out vec3 B, out vec3 C) {
   B = vec3(1.40301821, 0.231767504, 0.939056586);
   C = vec3(0.010579547, 0.0493226978, 112.405955);
}
void glassCoeffs_SF3(out vec3 B, out vec3 C) {
   B = vec3(1.57230542, 0.339661149, 1.03593712);
   C = vec3(0.012038218, 0.0531603583, 120.005381);
}
void glassCoeffs_SF4(out vec3 B, out vec3 C) {
   B = vec3(1.61957826, 0.339493189, 1.02566931);
   C = vec3(0.01255021, 0.0544559822, 117.652222);
}
void glassCoeffs_SF5(out vec3 B, out vec3 C) {
   B = vec3(1.46141885, 0.247713019, 0.949995832);
   C = vec3(0.011182613, 0.0508594669, 112.041888);
}
void glassCoeffs_SF6(out vec3 B, out vec3 C) {
   B = vec3(1.72448482, 0.390104889, 1.04572858);
   C = vec3(0.013487195, 0.0569318095, 118.557185);
}
void glassCoeffs_SF6HT(out vec3 B, out vec3 C) {
   B = vec3(1.72448482, 0.390104889, 1.04572858);
   C = vec3(0.013487195, 0.0569318095, 118.557185);
}
void glassCoeffs_SF10(out vec3 B, out vec3 C) {
   B = vec3(1.61625977, 0.259229334, 1.07762317);
   C = vec3(0.012753456, 0.0581983954, 116.60768);
}
void glassCoeffs_SF11(out vec3 B, out vec3 C) {
   B = vec3(1.73848403, 0.311168974, 1.17490871);
   C = vec3(0.01360686, 0.0615960463, 121.922711);
}
void glassCoeffs_SF56A(out vec3 B, out vec3 C) {
   B = vec3(1.70579259, 0.344223052, 1.09601828);
   C = vec3(0.01338747, 0.0579561608, 121.616024);
}
void glassCoeffs_SF57(out vec3 B, out vec3 C) {
   B = vec3(1.81651371, 0.428893641, 1.07186278);
   C = vec3(0.01437042, 0.0592801172, 121.419942);
}
void glassCoeffs_SF57HTultra(out vec3 B, out vec3 C) {
   B = vec3(1.81651371, 0.428893641, 1.07186278);
   C = vec3(0.01437042, 0.0592801172, 121.419942);
}
void glassCoeffs_N_KZFS11(out vec3 B, out vec3 C) {
   B = vec3(1.3322245, 0.28924161, 1.15161734);
   C = vec3(0.008402985, 0.034423972, 88.4310532);
}
void glassCoeffs_N_KZFS2(out vec3 B, out vec3 C) {
   B = vec3(1.23697554, 0.153569376, 0.903976272);
   C = vec3(0.007471705, 0.0308053556, 70.1731084);
}
void glassCoeffs_N_KZFS4(out vec3 B, out vec3 C) {
   B = vec3(1.35055424, 0.197575506, 1.09962992);
   C = vec3(0.008762821, 0.0371767201, 90.3866994);
}
void glassCoeffs_N_KZFS4HT(out vec3 B, out vec3 C) {
   B = vec3(1.35055424, 0.197575506, 1.09962992);
   C = vec3(0.008762821, 0.0371767201, 90.3866994);
}
void glassCoeffs_N_KZFS5(out vec3 B, out vec3 C) {
   B = vec3(1.47460789, 0.193584488, 1.26589974);
   C = vec3(0.009861438, 0.0445477583, 106.436258);
}
void glassCoeffs_N_KZFS8(out vec3 B, out vec3 C) {
   B = vec3(1.62693651, 0.24369876, 1.62007141);
   C = vec3(0.010880863, 0.0494207753, 131.009163);
}
void glassCoeffs_BK7G18(out vec3 B, out vec3 C) {
   B = vec3(1.26538542, 0.014419107, 1.00323028);
   C = vec3(0.008131041, 0.0543303226, 102.821166);
}
void glassCoeffs_F2G12(out vec3 B, out vec3 C) {
   B = vec3(1.34702224, 0.210037763, 19.5350768);
   C = vec3(0.009808506, 0.0471788018, 2279.1547);
}
void glassCoeffs_K5G20(out vec3 B, out vec3 C) {
   B = vec3(1.14094396, 0.14500119, 37.4705786);
   C = vec3(0.006949455, 0.0310574444, 4536.25624);
}
void glassCoeffs_LAK9G15(out vec3 B, out vec3 C) {
   B = vec3(1.28773667, 0.518244853, 26.1756109);
   C = vec3(0.005575419, 0.0223679524, 1892.2533);
}
void glassCoeffs_LF5G19(out vec3 B, out vec3 C) {
   B = vec3(1.34611327, 0.142428018, 0.900477176);
   C = vec3(0.009717439, 0.0501911619, 111.959703);
}
void glassCoeffs_SF6G05(out vec3 B, out vec3 C) {
   B = vec3(1.62113942, 0.506586092, 10.4032298);
   C = vec3(0.011347899, 0.0535840223, 1118.83658);
}
void glassCoeffs_SrTiO3(out vec3 B, out vec3 C) {
   B = vec3(3.042143, 1.170065, 30.83326);
   C = vec3(0.021783, 0.087207, 1101.314);
}
