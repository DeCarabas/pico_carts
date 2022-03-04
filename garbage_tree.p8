pico-8 cartridge // http://www.pico-8.com
version 35
__lua__
-- "a pretty tree" 
-- by john doty

-- based on what i saw in 
-- https://youtu.be/s6kxh_zyiqs
-- https://pyrofoux.itch.io/tea-garden

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
function skele(d)
 local i,l
 local s={}
 
 -- generate child branches
 if d>1 then
  for i=1,flr(rnd(3)) do
   for l in all(skele(d-1)) do
    add(s,l)
   end
  end
 end
 
 -- squish the branches into the
 -- upper half and move them to 
 -- the starting point.
 local delta=(0.5-rnd())/2
 for l in all(s) do
  l[1].x+=delta
  l[2].x+=delta
  l[1].y=0.4+l[1].y*0.6
  l[2].y=0.4+l[2].y*0.6
 end
 
 -- add our own line.
 add(s,{
  {x=0.5,       y=0},
  {x=0.5+delta, y=0.4}
 })
 return s
end

tree={}
function tree:new()
 local f={} 
 
 -- upside-down tree skele
 f.skeleton=skele(2)
 f.leaves={}
 for i=1,100 do
  local pt=rndc()
  pt.spr=flr(rnd(2)+1)
  add(f.leaves,pt)
 end
 
 f.flower=flower:new(3)
 f.flowers={}
 for i=1,20 do
  local pt=rndc()
  add(f.flowers,pt)
 end
 
 return setmetatable(f,{__index=self})
end

-- fill a quadrilateral with
-- slanty sides but flat tops
-- and bottoms.
function fill_quad(
 xul,xur,ytop,xll,xlr,ybot)
 local h=ybot-ytop
 local sl=(xll-xul)/h
 local ly
 
 for ly=ytop,ybot do
  local t=(ly-ytop)/h
  local xl=xul+t*(xll-xul)
  local xr=xur+t*(xlr-xur)
  local sw=mid(xr-xl,0,2)
  line(xl,ly,xr-sw,ly,4)
  line(xr-sw,ly,xr,ly,5)
 end
end

-- draw with x,y centered at 
-- bottom of trunk?
function tree:draw(x,y,age)
 local lx,ly

 local w,h=16,16

	-- full width/height at 0.5 
	local af=mid(age/0.5,0,1)
 w*=af h*=af  
 x-=flr(w/2) y-=flr(h) -- upper-left?
 
 for l in all(self.skeleton) do
  local tw=(1-l[2].y)*w*0.5
  local top_x=x+flr(l[2].x*w)
  local top_y=y+flr(h-l[2].y*h)
  
  local bw=(1-l[1].y)*w*0.5
  local bot_x=x+flr(l[1].x*w)
  local bot_y=y+flr(h-l[1].y*h)
  if tw and bw then
   fill_quad(
    flr(top_x-tw/2),ceil(top_x+tw/2),top_y,
    flr(bot_x-bw/2),ceil(bot_x+bw/2),bot_y)
  end
 end

	-- leaves from 0.2 to 0.6
	local leaf_cnt=#self.leaves
	leaf_cnt=flr(mid(
	 leaf_cnt*((age-0.2)/0.4),
	 0,
	 leaf_cnt))

	local leaf_i
	for leaf_i=1,leaf_cnt-1 do
	 local pt=self.leaves[leaf_i]
  lx=(4*af)+x+pt[1]*w 
  ly=y-(4*af)+pt[2]*h/2
  spr(pt.spr,lx,ly)
 end

	-- flowers from 0.4 to 1.0
	local flower_cnt=#self.flowers
	flower_cnt=flr(mid(
	 flower_cnt*((age-0.4)/0.6),
	 0,
	 flower_cnt))

 local flower_i
 for flower_i=1,flower_cnt-1 do
  local pt=self.flowers[flower_i]
  lx=x+(w/4)+pt[1]*w*0.75
  ly=y-pt[2]*h/2
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

-->8
-- util
function lerp(a,b,t)
 return a+(b-a)*t
end

-- random point within a unit 
-- circle
function rndc()
 local x,y=-1,-1
 while sqrt(x*x+y*y)>1 do
  x=1-rnd(2) y=1-rnd(2)
 end
 return {x,y}
end


__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700000bbbb00000bbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700000bbb300000bbbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0070070000b330000003bbb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000033b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
