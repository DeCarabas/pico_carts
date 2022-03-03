pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
the_balls={}

g_sc=4
draw_naive=true

function _update()
 local b
 if #the_balls<8 then
  b={x=rnd(128), y=128,
     s=rnd(4)+1, r=rnd(80)}
  if rnd()>0.7 then
   b.s=-b.s
   b.y=-b.r
  else
   b.y+=b.r
  end
  add(the_balls,b)
 end
 for b in all(the_balls) do
  b.y-=b.s
  if b.y<-b.r or b.y>128+b.r then
   del(the_balls,b)
  end
 end
 
 if btnp(❎) or btnp(🅾️) then
  draw_naive=not draw_naive
 end
 if btnp(⬆️) then
  g_sc*=2
 end
 if btnp(⬇️) and g_sc>1 then
  g_sc/=2
 end 
end

function balls(x,y)
 local v=0
 for b in all(the_balls) do
  local dx=x-b.x
  local dy=y-b.y
  v+=b.r/(dx*dx+dy*dy)
 end
 return mid(v,0,1)
end

ramp={0,1,2,4,9,9,10,10,10,7,7}

function compute(sc,bw)
 local bv,x,y={}
 for y=0,bw do 
  local fy=y*sc
  for x=0,bw do
   local fx=x*sc
   local v=balls(fx,fy)  
   add(bv,v)
  end
 end 
 return bv
end

function naive_draw(bv,sc,bw)
 local x,y
 local ramp=ramp

 for y=0,bw-1 do 
  local fy=y*sc
  for x=0,bw-1 do
   local fx=x*sc
   local v=bv[1+(y*(bw+1))+x]   
   local c=ramp[flr(v*#ramp)]
   rectfill(fx,fy,fx+sc,fy+sc,c)
  end
 end
end

function lerp_draw(bv,sc,bw)
 local x,y,xi,yi
 local ramp=ramp

 for y=0,bw-1 do
  local i=1+(y*(bw+1))
  local fy=y*sc
  for x=0,bw-1 do
   local fx=x*sc
   local v0,v1,v2,v3
   
   v0,v1=bv[i],bv[i+bw+1]
   local dy0=(v1-v0)/sc
   
   v2,v3=bv[i+1],bv[i+1+bw+1]
   local dy1=(v3-v2)/sc
   
   for yi=0,sc-1 do
    local dx=(v2-v0)/sc
    local v=v0
    for xi=0,sc-1 do
     local c=ramp[flr(v*#ramp)]
     pset(fx+xi,fy+yi,c)    
     v+=dx
    end
    v0+=dy0
    v2+=dy1
   end
   
   i+=1
  end
 end
end

function rnd_draw(bv,sc,bw)
 local x,y,xi,yi
 local ramp=ramp

 local d_sc=1/sc
 
 local fy=0
 for y=0,bw-1 do
  local y_frac=0
  for iy=0,sc-1 do
   local fx=0
   for x=0,bw-1 do
    local x_frac=0
    local bi=1+y*(bw+1)+x
    for ix=0,sc-1 do
    
     -- perturb index by jitter
     -- based on fraction thru
     -- square.
--     local si=bi
--     if rnd()<x_frac then
--      si+=1
--     end
--     if rnd()<y_frac then
--      si+=(bw+1)
--     end
--
--     -- now sample the values    
--     local v=bv[si]
--     if v==nil then
--      cls()
--      color(7)
--      print("x="..tostr(x).." y="..tostr(y))
--      print("fx="..tostr(fx).." fy="..tostr(fy).." #bv="..tostr(#bv).." bw="..tostr(bw))
--      print("ix="..tostr(ix).." bi="..tostr(bi).." si="..tostr(si))
--      ouijf()
--     end
--     local c=ramp[flr(v*#ramp)]
--     pset(fx,fy,c)
    
     fx+=1
     x_frac+=d_sc
    end -- for ix
   end -- for x
   
   fy+=1
   y_frac+=d_sc
  end -- for iy
 end -- for y
end

function _draw()
 cls()

 local sc=g_sc
 local bw=128/sc

 local bv=compute(sc,bw)
 if draw_naive then
  naive_draw(bv,sc,bw)
 else
  rnd_draw(bv,sc,bw)
 end
 print("cpu:"..tostr(stat(1)),0,0,7)
 print("sys:"..tostr(stat(2)),64,0,7)
 print("fps:"..tostr(stat(7)),0,10,7)
 print("sc:"..tostr(g_sc),64,10)
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
