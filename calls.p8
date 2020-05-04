pico-8 cartridge // http://www.pico-8.com
version 22
__lua__
-- birdsong generator
-- (c) 2020 john doty
--
-- generates random birdsong.
--

------------------------------
-- utilities
------------------------------
function lerp(a,b,t)
 return a+(b-a)*t
end

function repr(v)
 if type(v)=="table" then
  local r="{"
  local comma=false
  for k,v in pairs(v) do
   if comma then
    r=r..","
   end
   r=r..repr(k).."="..repr(v)
   comma=true
  end
  r=r.."}"
  return r
 elseif type(v)=="string" then
  return "\""..v.."\""
 elseif v==nil then
  return "nil"
 else
  return tostr(v)
 end
end

------------------------------
-- bird song
------------------------------
-- a chirp is a series of notes
-- (a single sound effect)
chirp={}
function chirp:new()
 local c={}

 -- i have found that it sounds 
 -- better if you lerp over 4 
 -- tones between points.
 -- 
 -- discontinuities sound gross,
 -- but you still want the pitch
 -- changes quick.
 local cl=rnd(8)+16
 local old=rnd(8)+56
 for i=0,cl,4 do
  local new=rnd(8)+56
  for j=0,3 do
   local pitch=lerp(old,new,j/4)
   add(c,flr(pitch))
  end
  old=new
 end
 
 return setmetatable(
  c,
  {__index=self}) 
end

-- load a chirp into an sfx slot
function chirp:load(i)
 local base=0x3200+(68*i)
 
 for i=0,63,1 do
  poke(base+i,0)
 end

 -- set speed to 1.
 poke(base+65,1) 

 -- set pitches. 
 local addr=base
 for pitch in all(self) do
  poke2(addr,0x0a00|pitch)
  addr+=2
 end 
end

-- a song is a series of chirps
song={}
function song:new()
 local notes={}
 for i=1,ceil(rnd(4)) do
  add(notes,chirp:new())
 end
 
 local s={
  -- these are in frames, or 
  -- 1/30 of a second.
  note_delay=rnd(5)+2,
 }
 for i=1,ceil(rnd(3)) do
  local ni=ceil(rnd(#notes))
  add(s, notes[ni])
 end

 return setmetatable(
  s,
  {__index=song})
end

function song:play(i,c)
 self.note_idx=0
 self.sfx=i
 self.channel=c
 self.delay=0
end

function song:update()
 local channel=self.channel
 
 -- if we're not playing or our
 -- assigned channel is busy
 -- then we do nothing.
 if(self.note_idx==nil) return
 if(stat(20+channel)>=0) return

 -- we're playing and our channel
 -- is clear, update our inter-
 -- note delay, see if it is 
 -- time for the next note.
 self.delay-=1
 if self.delay<0 then
  -- see if we have another note
  -- to play....
  if self.note_idx<#self then
   self.note_idx+=1
   
   -- load the new note into our
   -- assigned channel...
   self[self.note_idx]:load(
    self.sfx)
    
   -- ...and set it to play...
   sfx(self.sfx,channel)
   
   -- ...and then wait this long
   -- before we play the next 
   -- note.
   self.delay=self.note_delay   
  else
   -- reset us to be not playing
   -- anymore.
   self.note_idx=nil
  end
 end
end

-------------------------------
-- bird
-------------------------------
bird_colors={10,9,4,8}
bird_min=64
bird_max=100

function init_bird()
 bird_x=0 bird_y=(bird_max+bird_min)/2
 bird_state="incoming"
 bird_frame=3
 bird_color=bird_colors[flr(rnd(#bird_colors))+1]
 bird_song=song:new()
end

function move_bird()
 bird_x+=2
 bird_y=96-32*abs(64-bird_x)/64
 if bird_y>bird_max then bird_y=bird_max end
 
 bird_frame+=0.5
	if bird_frame>=4 then
	 bird_frame=2
	end
end

function update_bird()
 bird_song:update()
 if bird_state=="incoming" then
  move_bird()
  if bird_x>=64 then
   bird_x=64
   bird_state="sitting"
   bird_song:play(0,0)
  end
 elseif bird_state=="sitting" then
  bird_frame=1
 elseif bird_state=="leaving" then
  move_bird()
  if bird_x>128 then
   bird_x=0
   init_bird()
  end
 end
end

function draw_bird()
 rectfill(0,56,128,96,12)
 rectfill(0,96,128,128,11)

 local x,y=bird_x,bird_y
 spr(flr(bird_frame),x-4,y-8)
end

-------------------------------
-- yada
-------------------------------
function _init()
 init_bird()
 note_idx=0
 playing=false
 delay=0
end

function _update()
 -- todo: stop? reset?
 if btnp(🅾️) then
  bird_song:play(0,0)
 end
 if btnp(❎) then
  bird_state="leaving"
 end
 update_bird()
end

function _draw()
 cls(0)
 draw_bird()
 bird_song:draw(bird_color)
end

-- nb: this is a helper function 
-- that really shouldn't live 
-- anywhere but here. :p
function song:draw(tip_col)
 local pi,i,ni
 
 if self.channel~=nil then
  pi=stat(20+self.channel)
 end

 for ni=1,#self do
  local note=self[ni]
  for i=1,#note do
   local c,x=1,(ni-1)*32+i+1
   if ni==self.note_idx and 
      i==pi then
    c=7
   end
   
   -- pitch is 0-63, but we use
   -- so little of it! just take
   -- 32 off.
   local pitch=note[i]-32
   line(x,48,x,48-pitch,c)
   pset(x,48-pitch,tip_col)
  end
 end
end
__gfx__
00000000000000004440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000004400444044000000440000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000000044a0044444a0000044a4444444a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000444400044444000004440044444400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000004414000004440000044440000444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700004114000004440000044444000444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000444444000044400000444444004440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000aa0000440000004400044044000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100003305034050350503405032050300502c05028050230501d0501905016050140501305012050120501305014050180501e050250502b050300503305034050320502f0502805022050210502305024050
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001e00000000370503c0503c00000000000000000000000380503c05000000000003805035050380503505038050350500000000000000003800013000380503c050000000000000000000000000000000
000900003c050000003c05000000000000000000000000003c0503205032000320003205000000000000000032050000000000000000000000000000000000000000000000000000000000000000000000000000
00080000300503c0500000000000000003005030050300503c0502c0003c00030000230003c000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00100720070500a0500c0500f050110501605016050180501b0501b0501d050160501605016050180501b0501f0501f05022050220502705029050270502705027050220501f0502205022050220502405027050
