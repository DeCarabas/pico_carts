pico-8 cartridge // http://www.pico-8.com
version 22
__lua__
-- birdsong generator
-- (c) 2020 john doty
--
-- generates random birdsong.
--

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
-- song
------------------------------

function gen_chirp()
 local pitches={}
 
 -- it sounds better (i found) 
 -- if you lerp over 4 tones 
 -- between points. 
 -- discontinuities sound gross,
 -- but you still want the pitch
 -- changes quick.
 local cl=rnd(8)+16
 local old=rnd(8)+56
 for i=0,cl,4 do
  local new=rnd(8)+56
  for j=0,3 do
   local pitch=lerp(old,new,j/4)
   add(pitches,flr(pitch))
  end
  old=new
 end
 
 return pitches
end

function load_chirp(i,chirp)
 local base=0x3200+(68*i)
 
 for i=0,63,1 do
  poke(base+i,0)
 end

 -- set speed to 1.
 poke(base+65,1) 

 -- set pitches. 
 local addr=base
 for pitch in all(chirp) do
  poke2(addr,0x0a00|pitch)
  addr+=2
 end
end

function gen_song()
 local notes={}
 for i=1,ceil(rnd(4)) do
  add(notes,gen_chirp())
 end
 
 local song={}
 for i=1,ceil(rnd(3)) do
  local ni=ceil(rnd(#notes))
  add(song, notes[ni])
 end
 
 -- these are in frames, or 1/30
 -- of a second.
 song.note_delay=rnd(5)+2
 return song 
end

function load_song(song)
 for i=1,#song do
  load_chirp(i-1,song[i])
 end 
end

function update_song()
 if stat(20)==-1 then
  -- no note, where are we?   
  delay-=1
  if delay<0 then
   if note_idx<#song then
    note_idx+=1
    sfx(note_idx-1)
     
    -- when the note is done
    -- wait this amount of time
    delay=song.note_delay
    pd=delay
   else
    playing=false
    note_idx=0
   end
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
 song=gen_song()
 load_song(song)
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
 if bird_state=="incoming" then
  move_bird()
  if bird_x>=64 then
   bird_x=64
   bird_state="sitting"
	  playing=true
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
-- color(bird_color)
-- local b=bird[bird_frame]
-- line(x+b[1][1],y+b[1][2],
--      x+b[2][1],y+b[2][2])
-- for i=3,#b do
--  line(x+b[i][1],y+b[i][2])
-- end
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
 if btnp(🅾️) then
  playing=not playing
 end
 if btnp(❎) then
  note_idx=0
  bird_state="leaving"
 end
 if playing then
  update_song()
 end
 update_bird()
end

function _draw()
 cls(0)
 draw_bird()
 draw_song()
end

function draw_song()
 local i,ni
 
 for ni=1,#song do
	 local base=0x3200+(68*(ni-1))
  for i=0,31 do
   local pitch=peek(base+(i*2))
   if pitch>0 then
    local x=(ni-1)*32+i
    local c=1
    if ni==note_idx and 
       i==stat(20) then
     c=7
    end
    -- pitch is 0-63, but we use
    -- so little of it! just take
    -- 32 off.
    pitch-=32
    line(x,48,x,48-pitch,c)
    pset(x,48-pitch,bird_color)
   end
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
