{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1998 the Free Pascal development team

    SetJmp/Longjmp declarations

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

Type
  jmp_buf = record
    sp,fp,pc : Pointer;
  end;
  PJmp_buf = ^jmp_buf;

Function Setjmp (Var S : Jmp_buf) : longint; [external name 'FPC_SETJMP'];
Procedure longjmp (Var S : Jmp_buf; value : longint); [external name 'FPC_LONGJMP'];

