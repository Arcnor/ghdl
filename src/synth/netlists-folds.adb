--  Highler level API to build a netlist - do some optimizations.
--  Copyright (C) 2019 Tristan Gingold
--
--  This file is part of GHDL.
--
--  This program is free software; you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation; either version 2 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program; if not, write to the Free Software
--  Foundation, Inc., 51 Franklin Street - Fifth Floor, Boston,
--  MA 02110-1301, USA.

with Types_Utils; use Types_Utils;

with Netlists.Gates; use Netlists.Gates;
with Netlists.Locations;

package body Netlists.Folds is

   function Build2_Const_Uns (Ctxt : Context_Acc; Val : Uns64; W : Width)
                             return Net is
   begin
      if Val < 2**32 then
         return Build_Const_UB32 (Ctxt, Uns32 (Val), W);
      else
         pragma Assert (W > 32);
         declare
            Inst : Instance;
         begin
            Inst := Build_Const_Bit (Ctxt, W);
            Set_Param_Uns32 (Inst, 0, Uns32 (Val and 16#ffff_ffff#));
            Set_Param_Uns32 (Inst, 1, Uns32 (Shift_Right (Val, 32)));
            for I in 2 .. (W + 31) / 32 loop
               Set_Param_Uns32 (Inst, Param_Idx (I), 0);
            end loop;
            return Get_Output (Inst, 0);
         end;
      end if;
   end Build2_Const_Uns;

   function Build2_Const_Vec (Ctxt : Context_Acc; W : Width; V : Uns32_Arr)
                             return Net is
   begin
      if W <= 32 then
         return Build_Const_UB32 (Ctxt, V (V'First), W);
      else
         declare
            Inst : Instance;
         begin
            Inst := Build_Const_Bit (Ctxt, W);
            for I in V'Range loop
               Set_Param_Uns32 (Inst, Param_Idx (I - V'First), V (I));
            end loop;
            return Get_Output (Inst, 0);
         end;
      end if;
   end Build2_Const_Vec;

   function Build2_Const_Int (Ctxt : Context_Acc; Val : Int64; W : Width)
                             return Net is
   begin
      if Val in -2**31 .. 2**31 - 1 then
         return Build_Const_SB32 (Ctxt, Int32 (Val), W);
      else
         pragma Assert (W > 32);
         declare
            V : constant Uns64 := To_Uns64 (Val);
            S : constant Uns32 :=
              Uns32 (Shift_Right_Arithmetic (V, 63) and 16#ffff_ffff#);
            Inst : Instance;
         begin
            Inst := Build_Const_Bit (Ctxt, W);
            Set_Param_Uns32 (Inst, 0, Uns32 (V and 16#ffff_ffff#));
            Set_Param_Uns32 (Inst, 1, Uns32 (Shift_Right (V, 32)));
            for I in 2 .. (W + 31) / 32 loop
               Set_Param_Uns32 (Inst, Param_Idx (I), S);
            end loop;
            return Get_Output (Inst, 0);
         end;
      end if;
   end Build2_Const_Int;

   function Build2_Concat (Ctxt : Context_Acc; Els : Net_Array) return Net
   is
      F : constant Int32 := Els'First;
      Len : constant Natural := Els'Length;
      Wd : Width;
      Inst : Instance;
      N : Net;
   begin
      case Len is
         when 0 =>
            raise Internal_Error;
         when 1 =>
            N := Els (F);
         when 2 =>
            N := Build_Concat2 (Ctxt, Els (F + 1), Els (F));
         when 3 =>
            N := Build_Concat3 (Ctxt, Els (F + 2), Els (F + 1), Els (F));
         when 4 =>
            N := Build_Concat4
              (Ctxt, Els (F + 3), Els (F + 2), Els (F + 1), Els (F));
         when 5 .. Natural'Last =>
            --  Compute length.
            Wd := 0;
            for I in Els'Range loop
               Wd := Wd + Get_Width (Els (I));
            end loop;

            N := Build_Concatn (Ctxt, Wd, Uns32 (Len));
            Inst := Get_Net_Parent (N);
            for I in Els'Range loop
               Connect (Get_Input (Inst, Port_Idx (Els'Last - I)), Els (I));
            end loop;
      end case;
      return N;
   end Build2_Concat;

   function Build2_Uresize (Ctxt : Context_Acc;
                            I : Net;
                            W : Width;
                            Loc : Location_Type := No_Location)
                           return Net
   is
      Wn : constant Width := Get_Width (I);
      Res : Net;
   begin
      if Wn = W then
         return I;
      else
         if Wn > W then
            Res := Build_Trunc (Ctxt, Id_Utrunc, I, W);
         else
            pragma Assert (Wn < W);
            Res := Build_Extend (Ctxt, Id_Uextend, I, W);
         end if;
         Locations.Set_Location (Res, Loc);
         return Res;
      end if;
   end Build2_Uresize;

   function Build2_Extract
     (Ctxt : Context_Acc; I : Net; Off, W : Width) return Net is
   begin
      if Off = 0 and then W = Get_Width (I) then
         return I;
      else
         return Build_Extract (Ctxt, I, Off, W);
      end if;
   end Build2_Extract;
end Netlists.Folds;
