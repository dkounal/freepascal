{
    Copyright (c) 2020 by Nikolay Nikolov

    Contains the ASCII relocatable object file format (*.rel) reader and writer
    This is the object format used on the Z80 platforms.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit ogrel;

{$i fpcdefs.inc}

interface

    uses
       { common }
       cclasses,globtype,
       { target }
       systems,
       { assembler }
       cpuinfo,cpubase,aasmbase,assemble,link,
       { output }
       ogbase,
       owbase;

    type
      TRelRelocationFlag=(
        rrfByte,                              { bit  0 }
        rrfSymbol,                            { bit  1 }
        rrfPcRelative,                        { bit  2 }
        rrfTwoByteObjectFormatForByteData,    { bit  3 }
        rrfUnsignedByteData,                  { bit  4 }
        rrfPage0Reference,                    { bit  5 }
        rrfPageNNNReference,                  { bit  6 }
        rrfMSBWith2ByteMode,                  { bit  7 }
        rrfThreeByteObjectFormatForByteData,  { bit  8 }
        rrfRealMSBForThreeByteMode,           { bit  9 }
        rrfReserved10,                        { bit 10 }
        rrfReserved11);                       { bit 11 }
      TRelRelocationFlags=set of TRelRelocationFlag;

      { TRelRelocation }

      TRelRelocation = class(TObjRelocation)
      private
        function GetSecOrSymIdx: longint;
      public
        RelFlags: TRelRelocationFlags;
        HiByte: Byte;

        constructor CreateSymbol(ADataOffset:TObjSectionOfs;s:TObjSymbol;Atyp:TObjRelocationType);
        constructor CreateSection(ADataOffset:TObjSectionOfs;aobjsec:TObjSection;Atyp:TObjRelocationType);
        function EncodeFlags: string;
        property SecOrSymIdx: longint read GetSecOrSymIdx;
      end;

      { TRelObjData }

      TRelObjData = class(TObjData)
      public
        function sectionname(atype:TAsmSectiontype;const aname:string;aorder:TAsmSectionOrder):string;override;
        function sectiontype2align(atype:TAsmSectiontype):longint;override;
        procedure writeReloc(Data:TRelocDataInt;len:aword;p:TObjSymbol;Reloctype:TObjRelocationType);override;
      end;

      { TRelObjOutput }

      TRelObjOutput = class(tObjOutput)
      private
        procedure writeString(const S: ansistring);
        procedure writeLine(const S: ansistring);
        procedure WriteAreaContentAndRelocations(sec: TObjSection);
      protected
        function writeData(Data:TObjData):boolean;override;
      public
        constructor create(AWriter:TObjectWriter);override;
      end;

      { TRelAssembler }

      TRelAssembler = class(tinternalassembler)
        constructor create(info: pasminfo; smart:boolean);override;
      end;

      { TRelObjInput }

      TRelObjInput = class(TObjInput)
      private const
        MaxBufSize=512;
      private
        FBuf: array [0..MaxBufSize-1] of Char;
        FBufSize: Integer;
        FBufPos: Integer;

        function FillBuf: boolean;
        function AtEndOfBuf: boolean;
        function AtEoF: boolean;
        function ReadChar(out c: char): boolean;
        function PeekChar(out c: char): boolean;
        function ReadLine(out s: string): boolean;
      public
        constructor create;override;
        function ReadObjData(AReader:TObjectreader;out Data:TObjData):boolean;override;
        class function CanReadObjData(AReader:TObjectreader):boolean;override;
      end;

      { TIntelHexExeOutput }

      TIntelHexExeOutput = class(TExeOutput)
      protected
        function writeData:boolean;override;
        procedure DoRelocationFixup(objsec:TObjSection);override;
      public
        constructor create;override;
      end;

implementation

    uses
       SysUtils,
       cutils,verbose,globals,
       fmodule,aasmtai,aasmdata,
       ogmap,owar,
       version
       ;

    function tohex(q: qword): string;
      begin
        result:=HexStr(q,16);
        while (Length(result)>1) and (result[1]='0') do
          delete(result,1,1);
      end;

{*****************************************************************************
                              TRelRelocation
*****************************************************************************}

    function TRelRelocation.GetSecOrSymIdx: longint;
      begin
        if assigned(symbol) then
          result:=symbol.symidx
        else if assigned(objsection) then
          result:=objsection.SecSymIdx
        else
          internalerror(2020050502);
      end;

    constructor TRelRelocation.CreateSymbol(ADataOffset: TObjSectionOfs; s: TObjSymbol; Atyp: TObjRelocationType);
      begin
        inherited;
        case Atyp of
          RELOC_ABSOLUTE_HI8:
            begin
              size:=1;
              RelFlags:=[rrfSymbol,rrfByte,rrfTwoByteObjectFormatForByteData,rrfMSBWith2ByteMode];
            end;
          RELOC_ABSOLUTE_LO8:
            begin
              size:=1;
              RelFlags:=[rrfSymbol,rrfByte,rrfTwoByteObjectFormatForByteData];
            end;
          RELOC_ABSOLUTE:
            begin
              size:=2;
              RelFlags:=[rrfSymbol];
            end;
          else
            internalerror(2020050601);
        end;
      end;

    constructor TRelRelocation.CreateSection(ADataOffset: TObjSectionOfs; aobjsec: TObjSection; Atyp: TObjRelocationType);
      begin
        inherited;
        case Atyp of
          RELOC_ABSOLUTE_HI8:
            begin
              size:=1;
              RelFlags:=[rrfByte,rrfTwoByteObjectFormatForByteData,rrfMSBWith2ByteMode];
            end;
          RELOC_ABSOLUTE_LO8:
            begin
              size:=1;
              RelFlags:=[rrfByte,rrfTwoByteObjectFormatForByteData];
            end;
          RELOC_ABSOLUTE:
            begin
              size:=2;
              RelFlags:=[];
            end;
          else
            internalerror(2020050601);
        end;
      end;

    function TRelRelocation.EncodeFlags: string;
      var
        FlagsWord: Word;
      begin
        FlagsWord:=0;
        if rrfByte in RelFlags then
          Inc(FlagsWord,1);
        if rrfSymbol in RelFlags then
          Inc(FlagsWord,2);
        if rrfPcRelative in RelFlags then
          Inc(FlagsWord,4);
        if rrfTwoByteObjectFormatForByteData in RelFlags then
          Inc(FlagsWord,8);
        if rrfUnsignedByteData in RelFlags then
          Inc(FlagsWord,16);
        if rrfPage0Reference in RelFlags then
          Inc(FlagsWord,32);
        if rrfPageNNNReference in RelFlags then
          Inc(FlagsWord,64);
        if rrfMSBWith2ByteMode in RelFlags then
          Inc(FlagsWord,128);
        if rrfThreeByteObjectFormatForByteData in RelFlags then
          Inc(FlagsWord,256);
        if rrfRealMSBForThreeByteMode in RelFlags then
          Inc(FlagsWord,512);
        if rrfReserved10 in RelFlags then
          Inc(FlagsWord,1024);
        if rrfReserved11 in RelFlags then
          Inc(FlagsWord,2048);

        if (FlagsWord<=255) and ((FlagsWord and $F0)<>$F0) then
          Result:=HexStr(FlagsWord,2)
        else
          Result:=HexStr($F0 or Byte(FlagsWord shr 8),2)+' '+HexStr(Byte(FlagsWord),2);
      end;

{*****************************************************************************
                                TRelObjData
*****************************************************************************}

    function TRelObjData.sectionname(atype: TAsmSectiontype; const aname: string; aorder: TAsmSectionOrder): string;
      const
        secnames : array[TAsmSectiontype] of string[length('__DATA, __datacoal_nt,coalesced')] = ('','',
          '_CODE',
          '_DATA',
          '_DATA',
          '.rodata',
          '.bss',
          '.threadvar',
          '.pdata',
          '', { stubs }
          '__DATA,__nl_symbol_ptr',
          '__DATA,__la_symbol_ptr',
          '__DATA,__mod_init_func',
          '__DATA,__mod_term_func',
          '.stab',
          '.stabstr',
          '.idata$2','.idata$4','.idata$5','.idata$6','.idata$7','.edata',
          '.eh_frame',
          '.debug_frame','.debug_info','.debug_line','.debug_abbrev','.debug_aranges','.debug_ranges',
          '.fpc',
          '.toc',
          '.init',
          '.fini',
          '.objc_class',
          '.objc_meta_class',
          '.objc_cat_cls_meth',
          '.objc_cat_inst_meth',
          '.objc_protocol',
          '.objc_string_object',
          '.objc_cls_meth',
          '.objc_inst_meth',
          '.objc_cls_refs',
          '.objc_message_refs',
          '.objc_symbols',
          '.objc_category',
          '.objc_class_vars',
          '.objc_instance_vars',
          '.objc_module_info',
          '.objc_class_names',
          '.objc_meth_var_types',
          '.objc_meth_var_names',
          '.objc_selector_strs',
          '.objc_protocol_ext',
          '.objc_class_ext',
          '.objc_property',
          '.objc_image_info',
          '.objc_cstring_object',
          '.objc_sel_fixup',
          '__DATA,__objc_data',
          '__DATA,__objc_const',
          '.objc_superrefs',
          '__DATA, __datacoal_nt,coalesced',
          '.objc_classlist',
          '.objc_nlclasslist',
          '.objc_catlist',
          '.obcj_nlcatlist',
          '.objc_protolist',
          '.stack',
          '.heap',
          '.gcc_except_table',
          '.ARM.attributes'
        );
      begin
        result:=secnames[atype];
      end;

    function TRelObjData.sectiontype2align(atype:TAsmSectiontype):longint;
      begin
        result:=1;
      end;

    procedure TRelObjData.writeReloc(Data: TRelocDataInt; len: aword; p: TObjSymbol; Reloctype: TObjRelocationType);
      var
        bytes: array [0..1] of Byte;
        symaddr: QWord;
        objreloc: TRelRelocation;
      begin
        if CurrObjSec=nil then
          internalerror(200403072);
        objreloc:=nil;
        if assigned(p) then
          begin
            { real address of the symbol }
            symaddr:=p.address;

            if p.bind=AB_EXTERNAL then
              begin
                objreloc:=TRelRelocation.CreateSymbol(CurrObjSec.Size,p,Reloctype);
                if Reloctype in [RELOC_ABSOLUTE_HI8,RELOC_ABSOLUTE_LO8] then
                  objreloc.HiByte:=Byte(Data shr 8);
                CurrObjSec.ObjRelocations.Add(objreloc);
              end
            { relative relocations within the same section can be calculated directly,
              without the need to emit a relocation entry }
            else if (p.objsection=CurrObjSec) and
                    (p.bind<>AB_COMMON) and
                    (Reloctype=RELOC_RELATIVE) then
              begin
                data:=data+symaddr-len-CurrObjSec.Size;
              end
            else
              begin
                objreloc:=TRelRelocation.CreateSection(CurrObjSec.Size,p.objsection,Reloctype);
                inc(data,symaddr);
                if Reloctype in [RELOC_ABSOLUTE_HI8,RELOC_ABSOLUTE_LO8] then
                  objreloc.HiByte:=Byte(Data shr 8);
                CurrObjSec.ObjRelocations.Add(objreloc);
              end;
          end;
        case len of
          2:
            begin
              bytes[0]:=Byte(Data);
              bytes[1]:=Byte(Data shr 8);
              writebytes(bytes,2);
            end;
          1:
            begin
              bytes[0]:=Byte(Data);
              writebytes(bytes,1);
            end;
          else
            internalerror(2020050423);
        end;
      end;

{*****************************************************************************
                                TRelObjOutput
*****************************************************************************}

    procedure TRelObjOutput.writeString(const S: ansistring);
      begin
        FWriter.write(S[1],Length(S));
      end;

    procedure TRelObjOutput.writeLine(const S: ansistring);
      begin
        writeString(S+#10)
      end;

    procedure TRelObjOutput.WriteAreaContentAndRelocations(sec: TObjSection);
      const
        MaxChunkSize={14}7;
      var
        ChunkStart,ChunkLen, i: LongWord;
        ChunkFixupStart,ChunkFixupEnd, j, st_ofs: Integer;
        st,sr: ansistring;
        buf: array [0..MaxChunkSize-1] of Byte;
        reloc: TRelRelocation;
      begin
        if (oso_data in sec.SecOptions) and (sec.Data=nil) then
          internalerror(200403073);
        if assigned(sec.data) then
          sec.data.seek(0);
        ChunkFixupStart:=0;
        ChunkFixupEnd:=-1;
        ChunkStart:=0;
        ChunkLen:=Min(MaxChunkSize, sec.size-ChunkStart);
        while ChunkLen>0 do
        begin
          { find last fixup in the chunk }
          while (ChunkFixupEnd<(sec.ObjRelocations.Count-1)) and
                (TRelRelocation(sec.ObjRelocations[ChunkFixupEnd+1]).DataOffset<(ChunkStart+ChunkLen)) do
            inc(ChunkFixupEnd);
          { check if last chunk is crossing the chunk boundary, and trim ChunkLen if necessary }
          if (ChunkFixupEnd>=ChunkFixupStart) and
            ((TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).DataOffset+
              TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).size)>(ChunkStart+ChunkLen)) then
            begin
              ChunkLen:=TRelRelocation(sec.ObjRelocations[ChunkFixupEnd]).DataOffset-ChunkStart;
              Dec(ChunkFixupEnd);
            end;
          if ChunkLen>SizeOf(buf) then
            internalerror(2020050501);
          st:='T '+HexStr(Byte(ChunkStart),2)+' '+HexStr(Byte(ChunkStart shr 8),2);
          sr:='R 00 00 '+HexStr(Byte(sec.SecSymIdx),2)+' '+HexStr(Byte(sec.SecSymIdx shr 8),2);
          if assigned(sec.Data) then
            sec.Data.read(buf,ChunkLen)
          else
            FillChar(buf,ChunkLen,0);
          st_ofs:=1;
          { relocations present in the current chunk? }
          if ChunkFixupEnd>=ChunkFixupStart then
            begin
              j:=ChunkFixupStart;
              reloc:=TRelRelocation(sec.ObjRelocations[j]);
            end
          else
            begin
              j:=-1;
              reloc:=nil;
            end;
          for i:=0 to ChunkLen-1 do
            begin
              st:=st+' '+HexStr(buf[i],2);
              Inc(st_ofs);
              if assigned(reloc) then
                begin
                  { advance to the current relocation }
                  while (reloc.DataOffset<(ChunkStart+i)) and (j<ChunkFixupEnd) do
                    begin
                      Inc(j);
                      reloc:=TRelRelocation(sec.ObjRelocations[j]);
                    end;
                  { is there a relocation at the current position? }
                  if reloc.DataOffset=(ChunkStart+i) then
                    begin
                      sr:=sr+' '+reloc.EncodeFlags+' '+HexStr(st_ofs,2)+' '+HexStr(Byte(reloc.SecOrSymIdx),2)+' '+HexStr(Byte(reloc.SecOrSymIdx shr 8),2);
                      if reloc.typ in [RELOC_ABSOLUTE_HI8,RELOC_ABSOLUTE_LO8] then
                        begin
                          st:=st+' '+HexStr(reloc.HiByte,2);
                          Inc(st_ofs);
                        end;
                    end;
                end;
            end;
          writeLine(st);
          writeLine(sr);
          { prepare next chunk }
          Inc(ChunkStart, ChunkLen);
          ChunkLen:=Min(MaxChunkSize, sec.size-ChunkStart);
          ChunkFixupStart:=ChunkFixupEnd+1;
        end;
      end;

    function TRelObjOutput.writeData(Data: TObjData): boolean;
      var
        global_symbols_count: Integer = 0;
        secidx, idx, i, j: Integer;
        objsym: TObjSymbol;
        objsec: TObjSection;
      begin
        global_symbols_count:=0;
        for i:=0 to Data.ObjSymbolList.Count-1 do
          begin
            objsym:=TObjSymbol(Data.ObjSymbolList[i]);
            if objsym.bind in [AB_EXTERNAL,AB_GLOBAL] then
              Inc(global_symbols_count);
          end;

        writeLine('XL2');
        writeLine('H '+tohex(data.ObjSectionList.Count)+' areas '+tohex(global_symbols_count)+' global symbols');

        idx:=0;
        for i:=0 to Data.ObjSymbolList.Count-1 do
          begin
            objsym:=TObjSymbol(Data.ObjSymbolList[i]);
            if objsym.bind=AB_EXTERNAL then
              begin
                writeLine('S '+ApplyAsmSymbolRestrictions(objsym.Name)+' Ref0000');
                objsym.symidx:=idx;
                Inc(idx);
              end;
          end;
        secidx:=0;
        for i:=0 to Data.ObjSectionList.Count-1 do
          begin
            objsec:=TObjSection(Data.ObjSectionList[i]);
            writeLine('A '+objsec.Name+' size '+tohex(objsec.Size)+' flags 0 addr 0');
            objsec.SecSymIdx:=secidx;
            Inc(secidx);
            for j:=0 to Data.ObjSymbolList.Count-1 do
              begin
                objsym:=TObjSymbol(Data.ObjSymbolList[j]);
                if (objsym.bind=AB_GLOBAL) and (objsym.objsection=objsec) then
                  begin
                    writeLine('S '+ApplyAsmSymbolRestrictions(objsym.Name)+' Def'+HexStr(objsym.offset,4));
                    objsym.symidx:=idx;
                    Inc(idx);
                  end;
              end;
          end;
        for i:=0 to Data.ObjSectionList.Count-1 do
          begin
            objsec:=TObjSection(Data.ObjSectionList[i]);
            WriteAreaContentAndRelocations(objsec);
          end;
        result:=true;
      end;

    constructor TRelObjOutput.create(AWriter: TObjectWriter);
      begin
        inherited;
        cobjdata:=TRelObjData;
      end;

{*****************************************************************************
                                TRelAssembler
*****************************************************************************}

    constructor TRelAssembler.create(info: pasminfo; smart: boolean);
      begin
        inherited;
        CObjOutput:=TRelObjOutput;
        CInternalAr:=tarobjectwriter;
      end;


{*****************************************************************************
                                TRelObjInput
*****************************************************************************}

    function TRelObjInput.FillBuf: boolean;
      begin
        FBufPos:=0;
        FBufSize:=min(FReader.size-FReader.Pos,MaxBufSize);
        if FBufSize>0 then
          result:=FReader.read(FBuf,FBufSize)
        else
          result:=true;
      end;

    function TRelObjInput.AtEndOfBuf: boolean;
      begin
        result:=FBufPos=FBufSize;
      end;

    function TRelObjInput.AtEoF: boolean;
      begin
        result:=AtEndOfBuf and (FReader.Pos=FReader.size);
      end;

    function TRelObjInput.ReadChar(out c: char): boolean;
      begin
        c:=#0;
        if AtEndOfBuf then
          begin
            result:=FillBuf;
            if not result then
              exit;
          end;
        if not AtEndOfBuf then
          begin
            c:=FBuf[FBufPos];
            Inc(FBufPos);
            result:=true;
          end
        else
          result:=false;
      end;

    function TRelObjInput.PeekChar(out c: char): boolean;
      begin
        c:=#0;
        if AtEndOfBuf then
          begin
            result:=FillBuf;
            if not result then
              exit;
          end;
        if not AtEndOfBuf then
          begin
            c:=FBuf[FBufPos];
            result:=true;
          end
        else
          result:=false;
      end;

    function TRelObjInput.ReadLine(out s: string): boolean;
      var
        c: Char;
      begin
        s:='';
        if AtEoF then
          begin
            result:=false;
            exit;
          end;
        repeat
          if not AtEoF then
            begin
              if not ReadChar(c) then
                begin
                  result:=false;
                  exit;
                end;
              if not (c in [#13,#10]) then
                s:=s+c;
            end;
        until (c in [#13,#10]) or AtEoF;
        if (c=#13) and not AtEoF then
          begin
            if not PeekChar(c) then
              begin
                result:=false;
                exit;
              end;
            if c=#10 then
              begin
                if not ReadChar(c) then
                  begin
                    result:=false;
                    exit;
                  end;
              end;
          end;
        result:=true;
      end;

    constructor TRelObjInput.create;
      begin
        inherited create;
        cobjdata:=TRelObjData;
        FBufSize:=0;
        FBufPos:=0;
      end;

    function TRelObjInput.ReadObjData(AReader: TObjectreader; out Data: TObjData): boolean;
      const
        GenericRelErrMsg='Error reading REL file';
      var
        s: string;
        RecType: Char;
        HeaderFound: Boolean=false;
        ExpectedAreas,ExpectedSymbols: LongInt;
        tmpint: SizeInt;
      begin
        FReader:=AReader;
        InputFileName:=AReader.FileName;
        Data:=CObjData.Create(InputFileName);
        result:=false;
        s:='';
        repeat
          if AtEoF or not ReadLine(s) then
            begin
              InputError(GenericRelErrMsg);
              exit;
            end;
          s:=Trim(s);
        until s<>'';
        if s<>'XL2' then
          begin
            InputError('Invalid or unsupported REL format identifier');
            exit;
          end;
        while not AtEoF do
          begin
            if not ReadLine(s) then
              begin
                InputError(GenericRelErrMsg);
                exit;
              end;
            s:=Trim(s);
            if s<>'' then
              begin
                RecType:=s[1];
                if (length(s)<3) or (s[2]<>' ') then
                  begin
                    InputError('Invalid or unsupported REL record');
                    exit;
                  end;
                delete(s,1,2);
                case RecType of
                  'H': { header }
                    begin
                      if HeaderFound then
                        begin
                          InputError('Duplicated header');
                          exit;
                        end;
                      HeaderFound:=true;
                      tmpint:=Pos(' ',s);
                      if not TryStrToInt('$'+Copy(s,1,tmpint-1),ExpectedAreas) then
                        begin
                          InputError('Invalid area count in header');
                          exit;
                        end;
                      delete(s,1,tmpint);
                      if copy(s,1,6)<>'areas ' then
                        begin
                          InputError('Invalid header');
                          exit;
                        end;
                      delete(s,1,6);
                      tmpint:=Pos(' ',s);
                      if not TryStrToInt('$'+Copy(s,1,tmpint-1),ExpectedSymbols) then
                        begin
                          InputError('Invalid symbol count in header');
                          exit;
                        end;
                      delete(s,1,tmpint);
                      if s<>'global symbols' then
                        begin
                          InputError('Invalid header');
                          exit;
                        end;
                    end;
                  'M': { module }
                    begin
                      { we ignore this for now }
                    end;
                  'S': { symbol }
                    begin
                      { todo: implement }
                    end;
                  'A': { area }
                    begin
                      { todo: implement }
                    end;
                  'T': { T line () }
                    begin
                      { todo: implement }
                    end;
                  'R': { R line (relocation information) }
                    begin
                      { todo: implement }
                    end;
                  'P': { P line (paging information) }
                    begin
                      InputError('P line records are not supported');
                      exit;
                    end;
                  else
                    begin
                      InputError('Unsupported REL record type: #'+tostr(Ord(RecType)));
                      exit;
                    end;
                end;
              end;
          end;
      end;

    class function TRelObjInput.CanReadObjData(AReader: TObjectreader): boolean;
      var
        s: string;
        instance: TRelObjInput;
      begin
        result:=false;
        instance:=TRelObjInput.Create;
        instance.FReader:=AReader;
        with instance do
          while not AtEoF do
            begin
              if not ReadLine(s) then
                exit;
              s:=Trim(s);
              if s<>'' then
                begin
                  result:=s='XL2';
                  break;
                end;
            end;
        instance.Free;
      end;


{*****************************************************************************
                             TIntelHexExeOutput
*****************************************************************************}

    function TIntelHexExeOutput.writeData: boolean;
      begin
        result:=false;
      end;

    procedure TIntelHexExeOutput.DoRelocationFixup(objsec: TObjSection);
      begin
      end;

    constructor TIntelHexExeOutput.create;
      begin
        inherited create;
        CObjData:=TRelObjData;
      end;

{*****************************************************************************
                                  Initialize
*****************************************************************************}
    const
       as_z80_rel_info : tasminfo =
          (
            id     : as_z80_rel;
            idtxt  : 'REL';
            asmbin : '';
            asmcmd : '';
            supported_targets : [system_z80_embedded,system_z80_zxspectrum];
            flags : [af_outputbinary,af_smartlink_sections];
            labelprefix : '..@';
            labelmaxlen : 79;
            comment : '; ';
            dollarsign: '$';
          );

initialization
  RegisterAssembler(as_z80_rel_info,TRelAssembler);
end.
