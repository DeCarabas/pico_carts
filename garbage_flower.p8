pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
-- "a pretty flower" 
-- by john doty

-- based on what i saw in 
-- https://youtu.be/s6kxh_zyiqs
-- https://pyrofoux.itch.io/tea-garden

local flower_scale=2
local flower_size=6

function _init()
end

function _update()
 if btnp(⬆️) and flower_size<64 then
  flower_size+=2
  the_flower=nil
 end
 if btnp(⬇️) and flower_size>2 then
  flower_size-=2
  the_flower=nil
 end
 if btnp(⬅️) and flower_scale>1 then
  flower_scale-=1
 end
 if btnp(➡️) and flower_scale<10 then
  flower_scale+=1
 end
 
 if btnp(❎) or btnp(🅾️) or the_flower==nil then
  the_flower=flower:new(flower_size)
 end
end

function princ(txt,y,col)
 local x=64-flr((4*#txt-1)/2)
 print(txt,x,y,col)
end

function _draw()
 cls()
 princ("a pretty flower", 16, 7)
 princ("of "..tostr(flower_size).." pixels", 22, 7)
 the_flower:draw(64,64,flower_scale)
 princ("press 🅾️ or ❎ for another", 96, 7)
 princ("⬆️ and ⬇️ to grow and shrink", 102, 7)
 princ("⬅️ and ➡️ to zoom", 108, 7)
end
-->8
-- actual flower stuff.
flower={}
function flower:new(size)
 local f={size=size}
 local colors={}
 while colors[4]==colors[5] do
  colors={
   0,0,0,
   flr(rnd(8)+8),
   flr(rnd(8)+8)
  }
 end

 local symm=flr(rnd(2))
 for y=0,size-1 do
  for x=0,size-1 do
   local c=rnd(colors)
   f[y*size+x]=c
   if symm==0 then
    f[x*size+y]=c
   else
    f[y*size+(size-1-x)]=c
   end
  end
 end
 
 return setmetatable(f,{__index=self})
end

function flower:draw(x,y,scale)
 local sz=self.size
 
 x=flr(x-sz*scale/2)
 y=flr(y-sz*scale/2)
 
 for ly=0,(sz*scale)-1 do
  for lx=0,(sz*scale)-1 do
   local px=flr(lx/scale)
   local py=flr(ly/scale)
   local c=self[py*sz+px]
   if c~=0 then
    pset(x+lx,y+ly,c)
   end
  end
 end
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
