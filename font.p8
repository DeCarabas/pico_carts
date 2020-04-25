pico-8 cartridge // http://www.pico-8.com
version 22
__lua__
-- custom font builder
--
-- to make a new font:
-- 1. edit the font in the 
--    sprite sheet
-- 2. make sure the mapping 
--    from sprite to character
--    code below is correct.
-- 3. run the program, and make
--    sure that the font looks
--    right.
-- 4. copy the font to the 
--    clipboard.
-- 5. replace the [[..]] string
--    over in tab 2.
-- 6. copy tab 2 and paste it 
--    into your project.
--
mapping={}
for i=0,25 do
 mapping[i+1]=ord("a")+i-32
end
for i=0,25 do
 mapping[27+i]=ord("a")+i
end
for i=0,9 do
 mapping[53+i]=ord("0")+i
end
mapping[63]=ord("!")
mapping[64]=ord("?")
mapping[65]=ord(".")
mapping[66]=ord(":")
mapping[67]=ord(",")
mapping[68]=ord("'")
mapping[69]=ord("-")

function _init()
 hex=build_font(mapping)

 -- default to showing you the
 -- font from the spritesheet
 -- but save the original so you
 -- can toggle.
 orig_font=font_enc
 font_enc=hex
 load_font(hex)
end

copy_time=0
function _update()
 if btnp(❎) then
  if font_enc==orig_font then
   font_enc=hex
  else
   font_enc=orig_font
  end
  load_font(hex)
 end
 if btnp(🅾️) then
  printh("[["..hex.."]]","@clip")  
  copy_time=100
 elseif copy_time>0 then
  copy_time-=1
 end
end

function _draw()
 cls(0)
 draw_string(
  "^the quick brown fox jumped\n"..
  "over the lazy dog.",
  0,0,7)

 color(12)  
 draw_string(
  "^here's the whole alphabet:\n",
  0,25)
 color(10)
 draw_string(
  "^aa^bb^cc^dd^ee^ff^gg^hh^ii^jj^kk^ll^mm\n"..
  "^nn^oo^pp^qq^rr^ss^tt^uu^vv^ww^xx^yy\n"..
  "^zz0123456789!?.:,'-",
  0,35)
 
 color(11)
 draw_string(
  "^it takes "..#hex.." bytes "..
  "and 298\ntokens.",
  0,90)
 if copy_time>0 then
  draw_string(
   "^font copied!",0,120)
 else
  draw_string(
   "^press a button to copy the",
   0,110)
  draw_string(
   "font to your clipboard.",
   0,120)
 end
end

-->8
-- encoding

-- utilities
--
-- return a new table that is 
-- the merge of the a and b.
function merge(a,b)
 local new_tbl,k,v={}
 for k,v in pairs(a) do
  new_tbl[k]=v
 end
 for k,v in pairs(b) do
  new_tbl[k]=v
 end
 return new_tbl
end

-- return an array that is the
-- concatenation of two arrays
function concat(a,b)
 local r,i={}
 for i=1,#a do add(r,a[i]) end
 for i=1,#b do add(r,b[i]) end
 return r
end

-- return a new array that is 
-- the original array with an 
-- element to the end of it 
function cons(a,v)
 return concat(a,{v})
end

-- figure out the dimensions
-- of the sprite. we hold the 
-- bottom-left constant, and 
-- figure the height and width
-- are variable.
function analyze(s)
 local px=8*flr(s%16)
 local py=8*flr(s/16)

 local width=0
 local height=0
 
 for y=0,7 do
  for x=0,7 do
   local clr=sget(px+x,py+y)
   if clr~=0 then
    width=max(x+1,width)
    height=max(height,8-y)
   end
  end
 end
 
 return {w=width,h=height}
end

-- convert sprite s into an 
-- actual 1bpp bitmap, encoded
-- in a self-contained byte 
-- array.
function bitmap(s,w,h)
 local px=8*flr(s%16)
 local py=8*flr(s/16)
 
 local bytes={(w<<4|h)}
 
 local acc,bits=0,0
 for y=8-h,7 do
  for x=0,w-1 do
   local cur=sget(px+x,py+y)

   acc <<= 1
   if cur~=0 then
    acc |= 1
   end

   bits+=1
   if bits==8 then
    add(bytes,acc)
    acc=0 bits=0
   end
  end
 end
 
 if bits~=0 then
  while bits~=8 do
   acc <<= 1
   bits += 1
  end
  add(bytes,acc)
 end
 
 return bytes
end

-- construct glyphs for the
-- sprites from s to e 
-- (inclusive)
function build_glyphs(mapping)
 local glyphs={}
 for i,c in pairs(mapping) do
  r=analyze(i)

  add(glyphs,{
   c=c,
   w=r.w,
   h=r.h,
   bmap=bitmap(i,r.w,r.h)
  })
 end
 return glyphs
end

-- given a number from 0 to 16
-- return the corresponding hex
-- digit string
function hexdigit(b)
 return sub(
  "0123456789abcdef",b+1,b+1)
end

-- convert the specified byte
-- array to a string of hex 
-- digits.
function tohex(bytes)
 local txt=""
 for b in all(bytes) do
  txt=txt..hexdigit((b&0xf0)>>4)
  txt=txt..hexdigit(b&0x0f)
 end
 return txt
end

-- construct the encoded font
-- string.
function build_font(mapping)
 -- read the sprite sheet and
 -- build glyphs for the font.
 glyphs=build_glyphs(mapping)

 -- serialize all the glyphs 
 -- into a single byte array.
 stream={}
 for g in all(glyphs) do
  add(stream,g.c)
  stream=concat(stream,g.bmap)
 end

 -- convert the single byte 
 -- array into a hex string.
 return tohex(stream)
end
-->8
-- big font code
--
-- call load_font() then when
-- you want call draw_string()
-- to draw what you want. 
-- the font has upper case a-z,
-- lower case a-z, digits 0-9,
-- and some punctuation.
font_enc=[[414869999f994248caae999e4348699889964448e999999e4548f88e888f4648f88e888847486998b9964848999f99994918ff4a48111111964b48999e99994c488888888f4d58dd6b18c6314e489ddbb9994f48699999965048e99e8888515864a5295a4d5248e99e99995348698611965438e9249255489999999656588c6315294457588c6318d6aa58588a9442295159588c62a210845a48f122448f615664a52934624888e999966346698896644811799996654669f8966648254e4444674769971960684888e999996918bf6a48101111966b488899e9996c28aaa96d56556b18c46e46ad99996f466999967046699e8871466997117246ad9888734669429674384ba492754699999676568c54a21077568c6b5aa878568a884544794699971e7a46f1248f3048699bd996313859249732486911248f3348691211963448aaaf22223548f88e11963648698e99963748f11248883848699699963948699711112118fd3f5874622210042e11803a16902c2358272858002d44f000]]

function load_font()
 local enc,bytes=font_enc,{}
 for i=1,#enc,2 do
  add(bytes,tonum("0x"..sub(enc,i,i+1)))
 end
 
 local font,bi={},1
 while bi<#bytes do
  local c=bytes[bi] bi+=1
  
  local bmap={bytes[bi]}
  local b=bmap[1]
  local w,h=(b&0xf0)>>4,b&0x0f
  local bytec=ceil(w*h/8)
  for j=1,bytec do
   add(bmap,bytes[bi+j])
  end
  bi+=bytec+1
  
  font[c]={w=w,h=h,bmap=bmap}
 end
 
 _jd_font=font
end

-- render a single glyph at x,y
-- in the current color.
function draw_font_glyph(glyph,x,y)
 local bi,bits=2,0
 local bmap=glyph.bmap
 local byte=bmap[bi]
 for iy=8-glyph.h,7 do
  for ix=0,glyph.w-1 do
   if byte&0x80>0 then
    pset(x+ix,y+iy)    
   end
   -- advance bits
   byte<<=1 bits+=1
   if bits==8 then
    -- advance bytes
    bi+=1 byte=bmap[bi] bits=0
   end
  end
 end
end

-- render a string in the font
-- with the upper-left at x,y.
-- specify upper-case letters 
-- by prefixing them with a ^.
--
-- (e.g., "^e" renders an 
-- upper-case e.)
--
-- if c is provided, the current
-- color will be set to that 
-- color first.
function draw_string(str,x,y,c)
 if c~=nil then color(c) end
 local lx,ly=x,y
 local i,font=1,_jd_font
 while i<=#str do
  local c=sub(str,i,i) i+=1
  if c==" " then
   lx+=4
  elseif c=="\n" then
   lx=x ly+=10
  else
   if c=="^" then
    c=sub(str,i,i) i+=1
    c=ord(c)-32
   else
    c=ord(c)
   end
   
   local glyph=font[c]
   draw_font_glyph(glyph,lx,ly)
   lx+=glyph.w+1
  end
 end
end
__gfx__
00000000077000007700000007700000777000007777000077770000077000007007000070000000000700007007000070000000770770007007000007700000
00000000700700007070000070070000700700007000000070000000700700007007000070000000000700007007000070000000707070007707000070070000
00700700700700007070000070070000700700007000000070000000700700007007000070000000000700007007000070000000707070007707000070070000
00077000700700007770000070000000700700007770000077700000700000007777000070000000000700007770000070000000700070007077000070070000
00077000700700007007000070000000700700007000000070000000707700007007000070000000000700007007000070000000700070007077000070070000
00700700777700007007000070070000700700007000000070000000700700007007000070000000000700007007000070000000700070007007000070070000
00000000700700007007000070070000700700007000000070000000700700007007000070000000700700007007000070000000700070007007000070070000
00000000700700007770000007700000777000007777000070000000077000007007000070000000077000007007000077770000700070007007000007700000
77700000077000007770000007700000777000007007000070007000700070007000700070007000777700000000000070000000000000000007000000000000
70070000700700007007000070070000070000007007000070007000700070000707000070007000000700000000000070000000000000000007000000000000
70070000700700007007000070000000070000007007000070007000700070000707000070007000007000000770000077700000077000000777000007700000
77700000700700007770000007700000070000007007000070007000700070000070000007070000007000007007000070070000700700007007000070070000
70000000700700007007000000070000070000007007000007070000700070000070000000700000070000007007000070070000700000007007000077770000
70000000707700007007000000070000070000007007000007070000707070000707000000700000070000007007000070070000700000007007000070000000
70000000700700007007000070070000070000007007000007070000707070000707000000700000700000007007000070070000700700007007000070070000
70000000077070007007000007700000070000000770000000700000070700007000700000700000777700000770700007700000077000000770000007700000
00700000000000007000000070000000000700007000000070000000000000000000000000000000000000000000000000000000000000000700000000000000
07070000077000007000000000000000000000007000000070000000000000000000000000000000000000000000000000000000000000000700000000000000
07000000700700007770000070000000000700007007000070000000070700007070000007700000077000000770000070700000077000007770000070070000
77700000700700007007000070000000000700007007000070000000707070007707000070070000700700007007000077070000700700000700000070070000
07000000077700007007000070000000000700007770000070000000707070007007000070070000700700007007000070070000070000000700000070070000
07000000000700007007000070000000000700007007000070000000700070007007000070070000777000000777000070000000007000000700000070070000
07000000700700007007000070000000700700007007000070000000700070007007000070070000700000000007000070000000700700000700000070070000
07000000077000007007000070000000077000007007000007000000700070007007000007700000700000000007000070000000077000000700000007700000
00000000000000000000000000000000000000000770000007000000077000000770000070700000777700000770000077770000077000000770000070000000
00000000000000000000000000000000000000007007000077000000700700007007000070700000700000007007000000070000700700007007000070000000
70007000700070007000700070070000777700007007000007000000000700000007000070700000700000007000000000070000700700007007000070000000
70007000700070000707000070070000000700007077000007000000000700000070000077770000777000007770000000700000077000000777000070000000
07070000707070000070000070070000007000007707000007000000007000000007000000700000000700007007000007000000700700000007000070000000
07070000707070000070000007770000070000007007000007000000070000000007000000700000000700007007000070000000700700000007000070000000
00700000707070000707000000070000700000007007000007000000700000007007000000700000700700007007000070000000700700000007000000000000
00700000070700007000700077700000777700000770000077700000777700000770000000700000077000000770000070000000077000000007000070000000
07770000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70007000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70007000000000007000000000000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000000000000000000000000000000007777000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000000007000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000700000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
77707000000000000000000000007000000700000000700000000000000000000000000000007000000000000000000070000000000000000000000000700000
07007000000000000000000000000000000700000000700000000000000000000000000000070700000000000000000000000000000000000000000000700000
07007770007700000007700700707007700700700000777007070007700700070707000000070000770070007000000070700700707000770007700077700000
07007007070070000070070700707070070700700000700707707070070700070770700000777007007007070000000070700707070707007070070700700000
07007007077770000070070700707070000777000000700707007070070707070700700000070007007000700000000070700707070707007077770700700000
07007007070000000007770700707070000700700000700707000070070707070700700000070007007000700000000070700707000707770070000700700000
07007007070070000000070700707070070700700000700707000070070707070700700000070007007007070000007070700707000707000070070700700000
07007007007700000000070077007007700700700000077007000007700070700700700000070000770070007000000700077007000707000007700077000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000700700000000000007000000000000000000000000070000000000000000000000000000000000000000000000000000000000
00000000000000000000000000700700000000000007000000000000000000000000070000000770000000000000000000000000000000000000000000000000
07700700070077007070000007770777000770000007000770007777070070000007770077007007000000000000000000000000000000000000000000000000
70070700070700707707000000700700707007000007007007000007070070000070070700707007000000000000000000000000000000000000000000000000
70070070700777707007000000700700707777000007007007000070070070000070070700700777000000000000000000000000000000000000000000000000
70070070700700007000000000700700707000000007007007000700007770000070070700700007000000000000000000000000000000000000000000000000
70070007000700707000000000700700707007000007007007007000000070000070070700707007000000000000000000000000000000000000000000000000
07700007000077007000000000700700700770000000700770707777077700000007700077000770070000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c00c00000000000000000c00000000000c00c0000000000000000000c000000000c00000000000000000c0000000c0000000000c0000000000c0000000000000
c00c00000000000000000c00000000000c00c0000000000000000000c000000000c00000000000000000c0000000c0000000000c0000000000c0000000000000
c00c00cc00c0c000cc00c000cc000000ccc0ccc000cc000000c000c0ccc000cc00c000cc0000000cc000c000cc00ccc000cc000ccc000cc00ccc0c0000000000
cccc0c00c0cc0c0c00c0000c00c000000c00c00c0c00c00000c000c0c00c0c00c0c00c00c00000c00c00c00c00c0c00c0c00c00c00c0c00c00c0000000000000
c00c0cccc0c00c0cccc00000c00000000c00c00c0cccc00000c0c0c0c00c0c00c0c00cccc00000c00c00c00c00c0c00c0c00c00c00c0cccc00c0000000000000
c00c0c0000c0000c000000000c0000000c00c00c0c00000000c0c0c0c00c0c00c0c00c00000000c00c00c00ccc00c00c0c00c00c00c0c00000c00c0000000000
c00c0c00c0c0000c00c0000c00c000000c00c00c0c00c00000c0c0c0c00c0c00c0c00c00c00000c00c00c00c0000c00c0c00c00c00c0c00c00c0000000000000
c00c00cc00c00000cc000000cc0000000c00c00c00cc0000000c0c00c00c00cc000c00cc0000000cc0c00c0c0000c00c00cc0c00cc000cc000c0000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0aa00000000aa000a00000aa0000000aaa00000a0aaaa000000aaaa000a000aa0000000a00a0a0000a0a0000a000a0a00a0a0000a0000a00aa0aa00000000000
a00a0000000a0a00a0000a00a000000a00a0000a0a000000000a00000a0a0a00a00aa00a00a0a0000a000000a00000a00a0a0000a0000a00a0a0a00000000000
a00a00aa000a0a00aaa00a00a00aa00a00a00aaa0a00000aa00a00000a000a00a0a00a0a00a0aaa00a0a0000a000a0a00a0a00a0a0000a00a0a0a00a0a000000
a00a0a00a00aaa00a00a0a0000a00a0a00a0a00a0aaa00a00a0aaa00aaa00a0000a00a0aaaa0a00a0a0a0000a000a0aaa00a00a0a0000a00a000a0a0a0a00000
a00a0a00a00a00a0a00a0a0000a0000a00a0a00a0a0000aaaa0a00000a000a0aa00aaa0a00a0a00a0a0a0000a000a0a00a0aaa00a0000a00a000a0a0a0a00000
aaaa0a00a00a00a0a00a0a00a0a0000a00a0a00a0a0000a0000a00000a000a00a0000a0a00a0a00a0a0a0000a000a0a00a0a00a0a0000a00a000a0a000a00000
a00a0a00a00a00a0a00a0a00a0a00a0a00a0a00a0a0000a00a0a00000a000a00a0a00a0a00a0a00a0a0a0a00a0a0a0a00a0a00a0a0000a00a000a0a000a00000
a00a00aa0a0aaa000aa000aa000aa00aaa000aa00aaaa00aa00a00000a0000aa000aa00a00a0a00a0a0a00aa000a00a00a0a00a0aaaa00a0a000a0a000a00000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a00a0000000aa0000000aaa00000000aa00000000aaa00000000aa0000000aaa00a00a00a000000a000a0000000a000a0000000a000a0000000a000a00000000
aa0a000000a00a000000a00a000000a00a0000000a00a000000a00a0000000a000a00a00a000000a000a0000000a000a00000000a0a00000000a000a00000000
aa0a0a0a00a00a00aa00a00a00aa00a00a000aa00a00a0a0a00a00000aa000a00aaa0a00a0a00a0a000a0a000a0a000a0a000a00a0a00a000a0a000a0a00a000
a0aa0aa0a0a00a0a00a0aaa00a00a0a00a00a00a0aaa00aa0a00aa00a00a00a000a00a00a0a00a0a000a0a000a0a000a0a000a000a0000a0a000a0a00a00a000
a0aa0a00a0a00a0a00a0a0000a00a0a00a00a00a0a00a0a00a0000a00a0000a000a00a00a0a00a00a0a000a0a00a000a0a0a0a000a00000a00000a000a00a000
a00a0a00a0a00a0a00a0a0000aaa00a0aa000aaa0a00a0a0000000a000a000a000a00a00a0a00a00a0a000a0a00a0a0a0a0a0a00a0a0000a00000a0000aaa000
a00a0a00a0a00a0a00a0a0000a0000a00a00000a0a00a0a0000a00a0a00a00a000a00a00a0a00a00a0a0000a000a0a0a0a0a0a00a0a000a0a0000a000000a000
a00a0a00a00aa000aa00a0000a00000aa0a0000a0a00a0a00000aa000aa000a000a000aa000aa0000a00000a0000a0a000a0a00a000a0a000a000a000aaa0000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
aaaa0000000aa000a000aa000aa00a0a00aaaa00aa00aaaa00aa000aa00a00aaa0000000000a0000000000000000000000000000000000000000000000000000
000a000000a00a0aa00a00a0a00a0a0a00a0000a00a0000a0a00a0a00a0a0a000a000000000a0000000000000000000000000000000000000000000000000000
00a00aaaa0a00a00a00000a0000a0a0a00a0000a0000000a0a00a0a00a0a0a000a000a0000a00000000000000000000000000000000000000000000000000000
00a00000a0a0aa00a00000a000a00aaaa0aaa00aaa0000a000aa000aaa0a0000a000000000000000000000000000000000000000000000000000000000000000
0a00000a00aa0a00a0000a00000a000a00000a0a00a00a000a00a0000a0a000a0000000000000000000000000000000000000000000000000000000000000000
0a0000a000a00a00a000a000000a000a00000a0a00a0a0000a00a0000a0a000a00000a00a0000000000000000000000000000000000000000000000000000000
a0000a0000a00a00a00a0000a00a000a00a00a0a00a0a0000a00a0000a00000000000000a0000000000000000000000000000000000000000000000000000000
aaaa0aaaa00aa00aaa0aaaa00aa0000a000aa000aa00a00000aa00000a0a000a000a000a00000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b00b0000000b00000000b000000000000000000bbbb0bbbb00bb000000b0000000000b000000000000000000000000000000b000000bb000bb000bb000000000
b00b0000000b00000000b000000000000000000000b0b0000b00b00000b0000000000b000000000000000000000000000000b00000b00b0b00b0b00b00000000
b0bbb00000bbb00bb000b00b00bb000bb000000000b0b0000b00000000bbb00b00b0bbb00bb000bb0000000bb000b0b000bbb00000000b0b00b0b00b00000000
b00b0000000b00b00b00b00b0b00b0b00b0000000b00bbb00bbb000000b00b0b00b00b00b00b0b00b00000b00b00bb0b0b00b00000000b00bbb00bb000000000
b00b0000000b00b00b00bbb00bbbb00b00000000b000000b0b00b00000b00b0b00b00b00bbbb00b0000000b00b00b00b0b00b0000000b00000b0b00b00000000
b00b0000000b00b00b00b00b0b000000b000000b0000000b0b00b00000b00b00bbb00b00b000000b000000b00b00b00b0b00b000000b000000b0b00b00000000
b00b0000000b00b00b00b00b0b00b0b00b00000b0000b00b0b00b00000b00b0000b00b00b00b0b00b00000b00b00b00b0b00b00000b0000000b0b00b00000000
b00b0000000b000bb0b0b00b00bb000bb000000b00000bb000bb0000000bb00bbb000b000bb000bb0000000bb0b0b00b00bb000000bbbb0000b00bb000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b0000000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b0000000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb00bb00b00b00bb00b0b000bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b00b0b00b0b00b0bb0b0b00b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b00b0bbb00bbbb0b00b00b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b00b0b00b0b0000b00b000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b00b0b00b0b00b0b00b0b00b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b000bb00b00b00bb00b00b00bb00b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb000000000000000000000000000000000000b0000000000b000b00000000000000000b000000000000000000000000000000000000b00b000000000000000
b00b00000000000000000000000000000000000b0000000000b000b00000000000000000b000000000000000000000000000000000000b00b000000000000000
b00b0b0b000bb000bb000bb0000000bb0000000bbb00b00b0bbb0bbb00bb00b0b000000bbb00bb0000000bb000bb000bb00b00b00000bbb0bbb000bb00000000
bbb00bb0b0b00b0b00b0b00b00000b00b000000b00b0b00b00b000b00b00b0bb0b000000b00b00b00000b00b0b00b0b00b0b00b000000b00b00b0b00b0000000
b0000b00b0bbbb00b0000b0000000b00b000000b00b0b00b00b000b00b00b0b00b000000b00b00b00000b0000b00b0b00b0b00b000000b00b00b0bbbb0000000
b0000b0000b000000b0000b000000b00b000000b00b0b00b00b000b00b00b0b00b000000b00b00b00000b0000b00b0bbb000bbb000000b00b00b0b0000000000
b0000b0000b00b0b00b0b00b00000b00b000000b00b0b00b00b000b00b00b0b00b000000b00b00b00000b00b0b00b0b0000000b000000b00b00b0b00b0000000
b0000b00000bb000bb000bb0000000bb0b000000bb000bb000b000b000bb00b00b000000b000bb0000000bb000bb00b0000bbb0000000b00b00b00bb00000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00b0000000000000b0000000b0000000000000000000000000000000000000000b00b000000b00000000000000000000000b0000000000000000000000000000
0b0b000000000000b0000000b0000000000000000000000000000000000000000b000000000b00000000000000000000000b0000000000000000000000000000
0b0000bb00b0b00bbb00000bbb00bb000000b00b00bb00b00b0b0b0000000bb00b00b00bb00bbb000bb000bb000b0b000bbb0000000000000000000000000000
bbb00b00b0bb0b00b0000000b00b00b00000b00b0b00b0b00b0bb0b00000b00b0b00b0b00b0b00b0b00b0b00b00bb0b0b00b0000000000000000000000000000
0b000b00b0b00b00b0000000b00b00b00000b00b0b00b0b00b0b00b00000b0000b00b0b00b0b00b0b00b0b00b00b00b0b00b0000000000000000000000000000
0b000b00b0b00b00b0000000b00b00b000000bbb0b00b0b00b0b00000000b0000b00b0bbb00b00b0b00b0b00b00b0000b00b0000000000000000000000000000
0b000b00b0b00b00b0000000b00b00b00000000b0b00b0b00b0b00000000b00b0b00b0b0000b00b0b00b0b00b00b0000b00b0000000000000000000000000000
0b0000bb00b00b00b0000000b000bb000000bbb000bb000bb00b000000000bb000b0b0b00000bb000bb000bb0b0b00000bb00b00000000000000000000000000

