pico-8 cartridge // http://www.pico-8.com
version 35
__lua__
-- "a pretty tree"
-- by john doty

-- based on what i saw in
-- https://youtu.be/s6kxh_zyiqs
-- https://pyrofoux.itch.io/tea-garden


-- Need to save 511 tokens.

function _init()
end

local bug_age=0

function _update()
 if btnp(❎) or btnp(🅾️) then
  the_tree=nil
  bug_age=0
 end
 if the_tree==nil then
  the_tree=tree:new()
 end
 bug_age=mid(bug_age+0.01,0,1)
end

function princ(txt,y,col)
 local x=64-flr((4*#txt-1)/2)
 print(txt,x,y,col)
end

function _draw()
 cls()
 princ("a pretty tree", 16, 7)
 the_tree:draw(64,64,bug_age)
 princ("press 🅾️ or ❎ for another", 96, 7)
end
-->8
-- trees
-- function skele(d)
--  local i,l
--  local s={}

--  -- generate child branches
--  if d>1 then
--   for i=1,flr(rnd(3)) do
--    for l in all(skele(d-1)) do
--     add(s,l)
--    end
--   end
--  end

--  -- squish the branches into the
--  -- upper half and move them to
--  -- the starting point.
--  local delta=(0.5-rnd())/2
--  for l in all(s) do
--   l[1].x+=delta
--   l[2].x+=delta
--   l[1].y=0.4+l[1].y*0.6
--   l[2].y=0.4+l[2].y*0.6
--  end

--  -- add our own line.
--  add(s,{
--   {x=0.5,       y=0},
--   {x=0.5+delta, y=0.4}
--  })
--  return s
-- end

tree={}
function tree:new()
 local f={
  leaves={},
  flowers={}
 }

 -- upside-down tree skele
 -- f.skeleton=skele(2)
 for i=1,200 do
  local pt=rndc()
  pt.spr=rnd_int(2)+1
  add(f.leaves,pt)
 end

 f.flower=flower:new(3)
 for i=1,40 do
  add(f.flowers,rndc())
 end

 return setmetatable(f,{__index=self})
end

-- -- fill a quadrilateral with
-- -- slanty sides but flat tops
-- -- and bottoms.
-- function fill_quad(
--       xul,xur,ytop,xll,xlr,ybot)
--    local h=ybot-ytop
--    local sl=(xll-xul)/h
--    local ly

--    for ly=ytop,ybot do
--       local t=(ly-ytop)/h
--       local xl,xr=xul+t*(xll-xul),xur+t*(xlr-xur)
--       local sw=mid(xr-xl,0,2)
--       line(xl,ly,xr-sw,ly,4)
--       line(xr-sw,ly,xr,ly,5)
--    end
-- end

-- draw with x,y centered at
-- bottom of trunk?
function tree:draw(x,y,age)
   -- full width/height at 0.5
   local af=mid(age/0.5,0,1)

   local trunk_sz=flr(16*af)
   sspr(
     56,16,
     16,16,
     x-trunk_sz/2,y-trunk_sz,
     trunk_sz,trunk_sz)

   -- for l in all(self.skeleton) do
   --    local tw=(1-l[2].y)*w*0.5
   --    local top_x=x+flr(l[2].x*w)
   --    local top_y=y+flr(h-l[2].y*h)

   --    local bw=(1-l[1].y)*w*0.5
   --    local bot_x=x+flr(l[1].x*w)
   --    local bot_y=y+flr(h-l[1].y*h)
   --    if tw and bw then
   --       fill_quad(
   --          flr(top_x-tw/2),ceil(top_x+tw/2),top_y,
   --          flr(bot_x-bw/2),ceil(bot_x+bw/2),bot_y)
   --    end
   -- end


   -- full width/height at 0.5
   local sz=flr(24*af)
   x-=sz/2 y-=sz -- upper-left?


   function aged_count(start_age,span,count)
      return flr(mid(count*(age-start_age)/span,0,count))
   end

   -- leaves from 0.2 to 0.6
   af*=4
   for i=1,aged_count(0.2,0.4,#self.leaves)-1 do
      local pt=self.leaves[i]
      local lx=af+x+pt[1]*sz
      local ly=y-af+pt[2]*sz/2

      spr(pt.spr,lx,ly)
   end

   -- flowers from 0.4 to 1.0
   for i=1,aged_count(0.4,0.6,#self.flowers)-1 do
      local pt=self.flowers[i]
      local lx=x+(sz/4)+pt[1]*sz*0.75
      local ly=y-pt[2]*sz/2
      self.flower:draw(lx,ly,1)
   end
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
   rnd_int(8)+8,
   rnd_int(8)+8
  }
 end

 local symm=rnd_int(2)
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

-->8
-- random point within a unit
-- circle
function rnd_int(n)
  return flr(rnd(n))
end

function rndc()
 local x,y=-1,-1
 while sqrt(x*x+y*y)>1 do
  x=1-rnd(2) y=1-rnd(2)
 end
 return {x,y}
end


__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700001bbb100001110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700001bbbb10001bbb1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700001bbb310001bbbb100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070001b331000013bbb100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000111000000133b100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000999990000000000000000000000000000000000000000000000000000000000000000000000000
00000000000099999990000000000000000000000000000000999f00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000f99999900000000000000000000000000000004ff400000000000000000000000000000000000000000000000000000000000000000000000000
000000000000ffff9990000000000000000000000000000000ffff00000000000000000000000000000000000000000000000000000000000000000000000000
000000000000f4fff4f00000000000000000000000000000005555f0000000000000000000000000000000000000000000000000000000000000000000000000
000000000000ffeeeff0000000000000000000000000000000f55500000000000000000000000000000000000000000000000000000000000000000000000000
000000000000fffffff0000000000000000000000000000000555500000000000000000000000000000000000000000000000000000000000000000000000000
00000000000005555500000000000000000000000000000000f00f00000000000000000000000000000000000000000000000000000000000000000000000000
00000000000055555550000000000000000000000000000000000000444445551014451000000000000000000000000000000000000000000000000000000000
00000000000056666650000000000000000000000000000000000000144444555144551000000000000000000000000000000000000000000000000000000000
00000000000056666650000000000000000000000000000000000000144444455444551000000000000000000000000000000000000000000000000000000000
00000000000056666650000000000000000000000000000000000000144444444444551000000000000000000000000000000000000000000000000000000000
00000000000056666650000000000000000000000000000000000000014444444445551000000000000000000000000000000000000000000000000000000000
00000000000005555500000000000000000000000000000000000000000144444445551000000000000000000000000000000000000000000000000000000000
00000000000005000500000000000000000000000000000000000000000144444445510000000000000000000000000000000000000000000000000000000000
00000000000005000500000000000000000000000000000000000000001444444455510000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001444444455510000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001444444455100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000001444444555100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000014444444555100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000014444444555100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000014444445555100000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000144444455551000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000144444455551000000000000000000000000000000000000000000000000000000000000
