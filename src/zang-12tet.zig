const std = @import("std");

const semitone = std.math.pow(f32, 2.0, 1.0 / 12.0);

fn calcNoteFreq(note: i32) f32 {
    return std.math.pow(f32, semitone, @intToFloat(f32, note));
}

// note: these are relative frequencies, so you'll have to multiply the value
// by the value you want as a4 (such as 440.0)
pub const c0 = calcNoteFreq(-57);
pub const cs0 = calcNoteFreq(-56);
pub const db0 = calcNoteFreq(-56);
pub const d0 = calcNoteFreq(-55);
pub const ds0 = calcNoteFreq(-54);
pub const eb0 = calcNoteFreq(-54);
pub const e0 = calcNoteFreq(-53);
pub const f0 = calcNoteFreq(-52);
pub const fs0 = calcNoteFreq(-51);
pub const gb0 = calcNoteFreq(-51);
pub const g0 = calcNoteFreq(-50);
pub const gs0 = calcNoteFreq(-49);
pub const ab0 = calcNoteFreq(-49);
pub const a0 = calcNoteFreq(-48);
pub const as0 = calcNoteFreq(-47);
pub const bb0 = calcNoteFreq(-47);
pub const b0 = calcNoteFreq(-46);
pub const c1 = calcNoteFreq(-45);
pub const cs1 = calcNoteFreq(-44);
pub const db1 = calcNoteFreq(-44);
pub const d1 = calcNoteFreq(-43);
pub const ds1 = calcNoteFreq(-42);
pub const eb1 = calcNoteFreq(-42);
pub const e1 = calcNoteFreq(-41);
pub const f1 = calcNoteFreq(-40);
pub const fs1 = calcNoteFreq(-39);
pub const gb1 = calcNoteFreq(-39);
pub const g1 = calcNoteFreq(-38);
pub const gs1 = calcNoteFreq(-37);
pub const ab1 = calcNoteFreq(-37);
pub const a1 = calcNoteFreq(-36);
pub const as1 = calcNoteFreq(-35);
pub const bb1 = calcNoteFreq(-35);
pub const b1 = calcNoteFreq(-34);
pub const c2 = calcNoteFreq(-33);
pub const cs2 = calcNoteFreq(-32);
pub const db2 = calcNoteFreq(-32);
pub const d2 = calcNoteFreq(-31);
pub const ds2 = calcNoteFreq(-30);
pub const eb2 = calcNoteFreq(-30);
pub const e2 = calcNoteFreq(-29);
pub const f2 = calcNoteFreq(-28);
pub const fs2 = calcNoteFreq(-27);
pub const gb2 = calcNoteFreq(-27);
pub const g2 = calcNoteFreq(-26);
pub const gs2 = calcNoteFreq(-25);
pub const ab2 = calcNoteFreq(-25);
pub const a2 = calcNoteFreq(-24);
pub const as2 = calcNoteFreq(-23);
pub const bb2 = calcNoteFreq(-23);
pub const b2 = calcNoteFreq(-22);
pub const c3 = calcNoteFreq(-21);
pub const cs3 = calcNoteFreq(-20);
pub const db3 = calcNoteFreq(-20);
pub const d3 = calcNoteFreq(-19);
pub const ds3 = calcNoteFreq(-18);
pub const eb3 = calcNoteFreq(-18);
pub const e3 = calcNoteFreq(-17);
pub const f3 = calcNoteFreq(-16);
pub const fs3 = calcNoteFreq(-15);
pub const gb3 = calcNoteFreq(-15);
pub const g3 = calcNoteFreq(-14);
pub const gs3 = calcNoteFreq(-13);
pub const ab3 = calcNoteFreq(-13);
pub const a3 = calcNoteFreq(-12);
pub const as3 = calcNoteFreq(-11);
pub const bb3 = calcNoteFreq(-11);
pub const b3 = calcNoteFreq(-10);
pub const c4 = calcNoteFreq(-9);
pub const cs4 = calcNoteFreq(-8);
pub const db4 = calcNoteFreq(-8);
pub const d4 = calcNoteFreq(-7);
pub const ds4 = calcNoteFreq(-6);
pub const eb4 = calcNoteFreq(-6);
pub const e4 = calcNoteFreq(-5);
pub const f4 = calcNoteFreq(-4);
pub const fs4 = calcNoteFreq(-3);
pub const gb4 = calcNoteFreq(-3);
pub const g4 = calcNoteFreq(-2);
pub const gs4 = calcNoteFreq(-1);
pub const ab4 = calcNoteFreq(-1);
pub const a4 = calcNoteFreq(0);
pub const as4 = calcNoteFreq(1);
pub const bb4 = calcNoteFreq(1);
pub const b4 = calcNoteFreq(2);
pub const c5 = calcNoteFreq(3);
pub const cs5 = calcNoteFreq(4);
pub const db5 = calcNoteFreq(4);
pub const d5 = calcNoteFreq(5);
pub const ds5 = calcNoteFreq(6);
pub const eb5 = calcNoteFreq(6);
pub const e5 = calcNoteFreq(7);
pub const f5 = calcNoteFreq(8);
pub const fs5 = calcNoteFreq(9);
pub const gb5 = calcNoteFreq(9);
pub const g5 = calcNoteFreq(10);
pub const gs5 = calcNoteFreq(11);
pub const ab5 = calcNoteFreq(11);
pub const a5 = calcNoteFreq(12);
pub const as5 = calcNoteFreq(13);
pub const bb5 = calcNoteFreq(13);
pub const b5 = calcNoteFreq(14);
pub const c6 = calcNoteFreq(15);
pub const cs6 = calcNoteFreq(16);
pub const db6 = calcNoteFreq(16);
pub const d6 = calcNoteFreq(17);
pub const ds6 = calcNoteFreq(18);
pub const eb6 = calcNoteFreq(18);
pub const e6 = calcNoteFreq(19);
pub const f6 = calcNoteFreq(20);
pub const fs6 = calcNoteFreq(21);
pub const gb6 = calcNoteFreq(21);
pub const g6 = calcNoteFreq(22);
pub const gs6 = calcNoteFreq(23);
pub const ab6 = calcNoteFreq(23);
pub const a6 = calcNoteFreq(24);
pub const as6 = calcNoteFreq(25);
pub const bb6 = calcNoteFreq(25);
pub const b6 = calcNoteFreq(26);
pub const c7 = calcNoteFreq(27);
pub const cs7 = calcNoteFreq(28);
pub const db7 = calcNoteFreq(28);
pub const d7 = calcNoteFreq(29);
pub const ds7 = calcNoteFreq(30);
pub const eb7 = calcNoteFreq(30);
pub const e7 = calcNoteFreq(31);
pub const f7 = calcNoteFreq(32);
pub const fs7 = calcNoteFreq(33);
pub const gb7 = calcNoteFreq(33);
pub const g7 = calcNoteFreq(34);
pub const gs7 = calcNoteFreq(35);
pub const ab7 = calcNoteFreq(35);
pub const a7 = calcNoteFreq(36);
pub const as7 = calcNoteFreq(37);
pub const bb7 = calcNoteFreq(37);
pub const b7 = calcNoteFreq(38);
pub const c8 = calcNoteFreq(39);
pub const cs8 = calcNoteFreq(40);
pub const db8 = calcNoteFreq(40);
pub const d8 = calcNoteFreq(41);
pub const ds8 = calcNoteFreq(42);
pub const eb8 = calcNoteFreq(42);
pub const e8 = calcNoteFreq(43);
pub const f8 = calcNoteFreq(44);
pub const fs8 = calcNoteFreq(45);
pub const gb8 = calcNoteFreq(45);
pub const g8 = calcNoteFreq(46);
pub const gs8 = calcNoteFreq(47);
pub const ab8 = calcNoteFreq(47);
pub const a8 = calcNoteFreq(48);
pub const as8 = calcNoteFreq(49);
pub const bb8 = calcNoteFreq(49);
pub const b8 = calcNoteFreq(50);
