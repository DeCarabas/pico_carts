pico-8 cartridge // http://www.pico-8.com
version 35
__lua__
-- robo gardening game
-- (c) 2020 john doty
--
-- == events? ==
-- [ ] rain
-- [ ] earthquake
-- [ ] wind storm
-- [ ] lightning & fires
--
-- :todo: zelda rock sprites
-- :todo: tweak power usage

-- the map is divided into 4
-- regions, horizontally.
-- x=[0,32)   base layer
-- x=[32,64)  item sprite layer
-- x=[64,96)  ?? water level?
-- x=[96,128) ??
--
-- in theory we can do so much
-- here but we have to be able
-- to save our game in 256 bytes
-- and there's only so much we
-- can throw away when we load
function place_rand(count, sp)
   local cnt=0
   while cnt<count do
      local x=1+flr(rnd(14))
      local y=1+flr(rnd(14))
      if not map_flag(x,y,1) then
         mset(x+32,y,sp)
         cnt+=1
      end
   end
end

-- game progress
--  chapter 0: pre-intro
--  chapter 1: walking/no charge
--  chapter 2: clear field
--  chapter 3: till and plant
function new_game()
   chapter=0
   base_x=2+flr(rnd(12))
   base_y=3+flr(rnd(8))
   day=0
   hour=8
   px=base_x
   py=base_y
   grabbed_item=nil

   -- init the item sprite layer
   place_rand(20,144) --grass
   place_rand(20,145) --grass
   place_rand(20,146) --grass
   place_rand(20,147) --grass
   place_rand(70,160) --rock

   -- clear off base
   for y=base_y-1,base_y+1 do
      for x=base_x-1,base_x+1 do
         mset(x+32,y,0)
      end
   end

   -- HAXXX
   add(flower_seeds, flower:new(flower_size,0))
end

stream={}
function stream:new_write(address, limit)
   return setmetatable(
      {buffer=0,bits=8,address=address,limit=limit},
      {__index=self})
end
function stream:new_read(address, limit)
   return setmetatable(
      {buffer=0,bits=0,address=address,limit=limit},
      {__index=self})
end
function stream:read()
   assert(self.limit > 0)
   self.limit-=1
   self.address+=1

   return @(self.address-1)
end
function stream:read2()
   assert(self.limit > 1)
   self.limit-=2
   self.address+=2
   return %(self.address-2)
end
function stream:unpack(width)
   local buffer = self.buffer
   local bits = self.bits

   local result = 0
   while width > 0 do
      if bits == 0 then
         assert(self.limit > 0) self.limit -= 1
         buffer = @self.address
         self.address += 1
         bits = 8
      end

      local consume = min(bits, width)
      result = (result << consume) | (buffer >> (bits - consume))
      result &= 0xFF -- the remaining bits must not go into the fraction
      bits -= consume
      buffer &= ((1<<bits) - 1)
      width -= consume
   end

   self.buffer = buffer
   self.bits = bits
   return result
end
function stream:write(v)
   if (v==nil) v=0
   assert(v>=0 and v<256)
   assert(self.limit > 0)
   self.limit -= 1

   poke(self.address, v)
   self.address+=1
end
function stream:write2(v)
   assert(self.limit > 1)
   self.limit -= 2

   poke2(self.address, v)
   self.address+=2
end
function stream:pack(width, ...)
   local bits=self.bits
   local buffer=self.buffer
   local values={...}

   for v in all(values) do
      local remaining = width
      assert(v>=0 and v<(1<<remaining))
      while remaining > 0 do
         local consume = min(bits, remaining)
         buffer = (buffer << consume) | (v >> (remaining - consume))
         bits -= consume
         if bits == 0 then
            poke(self.address, buffer)
            assert(self.limit > 0) self.limit -= 1
            self.address+=1
            bits = 8
            buffer = 0
         end
         remaining -= consume
         v &= ((1<<remaining) - 1)
      end
   end

   self.buffer=buffer
   self.bits=bits
end
function stream:flush()
   assert(self.bits==8 and self.buffer==0)
end

--[[
function test_pack()
   local s=stream:new_write(0x8000,256)
   for i=1,8 do
      s:pack(6, i)
   end
   s=stream:new_read(0x8000,256)
   for i=1,8 do
      local v=s:unpack(6)
      assert(v==i, v.." "..i)
   end
   print("pass")
end
]]

-- list all the sprite values that can be saved here.
-- we store the index in this list (so it can fit in
-- 5 bits!) rather than the raw sprite index itself.
save_item_code={0, 160, 144, 145, 146, 147}

function save_game()
   -- note: we work very hard to get in our 256 bytes here
   --       so that save-games work in the web player. we
   --       could theoretically use cstore() to let us save
   --       way more data, but that comes with other limits
   -- compare with load_game
   local w = stream:new_write(0x5e00,256)

   -- write a version byte first so that we know if there's
   -- a savegame or not. We should probably find something
   -- to pack in here but....
   w:write(0x02)             -- 1

   -- pack in various things. the map coordinates can always
   -- be packed into a single byte because they have a max
   -- of 15.
   w:pack(4, base_x, base_y) -- 2

   -- all these have more than 4 bits of value. (chapter
   -- probably doesn't more than 4 but ... it's not worth
   -- packing it up more)
   w:write(chapter)          -- 3
   w:write((day+1)%112)      -- 4
   -- hour = 8
   -- tank_level = 100
   -- energy_level = 100
   w:write(grabbed_item)     -- 5

   -- now pack up the seeds. we can have 16 flower seeds,
   -- and each uses two bytes, so we use 32 bytes here.
   for fi=1,16 do
      if fi<=#flower_seeds then
         w:write2(flower_seeds[fi].seed<<16)
      else
         w:write2(0)
      end
   end                      -- 37

   -- now pack up the items. each item gets 6 bits.
   -- the high bits are the signal bits:
   --
   --   0b0xxxxx     xxxxx = raw sprite index
   --   0b1axxxx     xxxx  = seed index, a = age
   --                        (0=half grown, 1=full grown)
   --
   -- 16*16*6/8 = 192 bytes
   for y=0,15 do
      for x=0,15 do
         local encoded=nil
         local item = mget(x+32, y)
         if item==148 then
            -- placeholder for a flower.
            -- first we need to find the flower...
            for fi=1,#flowers do
               local flower=flowers[fi]
               if flower.x==x and flower.y==y then
                  -- found the flower. now we need to find
                  -- the seed index....
                  for si=1,#flower_seeds do
                     if flower.seed==flower_seeds[si] then
                        -- set the high bit to indicate that
                        -- this is a seed index (which is
                        -- in [1-16] anyway.) the next bit
                        -- indicates whether the flower is
                        -- old or young.
                        encoded = 0b100000 | si
                        if flower.age > 0.5 then
                           encoded |= 0b010000
                        end
                        written=true
                        break
                     end
                  end
                  break
               end
            end
         else
            for ii=1,#save_item_code do
               if save_item_code[ii]==item then
                  encoded = ii
                  written=true
                  break
               end
            end
         end
         w:pack(6, encoded)
      end
   end
   w:flush()                       -- 229

   -- 27 bytes to spare! tree seeds maybe! :)
end

function load_game()
   -- reset the cart...
   reload()

   -- see save_game for details
   local w = stream:new_read(0x5e00,256)

   if w:read() ~= 0x02 then
      return false
   end

   base_x = w:unpack(4)
   base_y = w:unpack(4)
   px = base_x
   py = base_y

   chapter = w:read()
   day = w:read()
   hour = 8
   tank_level = 100
   energy_level = 100
   grabbed_item = w:read()
   if grabbed_item == 0 then
      grabbed_item = nil
   end

   flower_seeds={}
   for fi=1,16 do
      local seed = w:read2()
      if seed ~= 0 then
         add(flower_seeds, flower:new(flower_size, fi-1, seed>>16))
      end
   end                      -- 39

   -- unpack the items. each item gets 6 bits.
   -- the high bits are the signal bits:
   --
   --   0b0xxxxx     xxxxx = raw sprite index
   --   0b1axxxx     xxxx = seed index, a = age
   --                       (0=half grown, 1=full grown)
   --
   -- 16*16*6/8 = 192 bytes
   flowers={}
   for y=0,15 do
      for x=0,15 do
         local encoded = w:unpack(6)
         if encoded & 0b100000 ~= 0 then -- flower
            local age, si = 0.5, encoded & 0b001111
            if encoded & 0b010000 ~= 0 then
               age = 1.0
            end

            assert(si>0 and si<=#flower_seeds, x.." "..y.." "..si)
            add_flower(flower_seeds[si], age, x, y)
         else
            mset(32+x, y, save_item_code[encoded])
         end
      end
   end

   -- deal with the chapters.
   if chapter==2 then
      start_ch2()
   elseif chapter==3 then
      start_ch3()
   else
      penny:show(16,16,0)
   end

   return true
end

-- player state
function init_player()
   d=2 spd=0.125 walking=false
   idle_time=0

   max_tank=100
   tank_level=max_tank

   max_energy=100
   energy_level=max_energy
   walk_cost=0.2
   grab_cost=1
   plow_cost=1
   water_cost=0.5
   plant_cost=0.5

   tx=px ty=py

   animation=nil
   anim_index=nil
   anim_duration=nil
   anim_done=nil
end

-- menu state
function init_menu()
   menu_mode=false
   menu_sel=1
   menu_items={}
end

-- days are 24 hrs long
-- this is how much of an hr we
-- tick every frame. (tweak for
-- fun!)
function init_time()
   hour_inc=0.0036 --*100

   recharge_rate=100*hour_inc/4
   water_rate=100*hour_inc/2
   flower_rate=1*hour_inc/24
end

function init_base()
   -- the base points.
   mset(base_x-1,base_y,83)
   mset(base_x+1,base_y,83)
   mset(base_x,base_y,114)
end

function init_game()
   blank_screen=false

   init_items()
   init_plants()
   init_menu()
   init_time()
   init_base()
   init_player()
   init_weather()
   init_water()
   init_text()

   update_fn = update_walk
end

flower_sy=88

function _init()
   poke(0x5f36,0x40) -- disable print scroll
   flower:init(flower_sy)

   cartdata("doty_robo_p8")

   load_font()
   init_fx()

   new_game()
   init_game()

   -- cheatz
   menuitem(1,"+energy",function() energy_level=max_energy end)
   menuitem(2,"-energy",function() energy_level=mid(max_energy,0,energy_level/2) end)
   menuitem(3,"+8hrs",function() hour+=8 end)
   menuitem(4,"load", function()
               if load_game() then
                  init_game()
               end
   end)

   if chapter == 0 then
      do_script(cs_intro)
   end
end

function open_item_menu()
   menu_mode=true
   menu_sel=item_sel
   menu_items=get_items()
   update_fn=update_menu
end

function looking_at()
   if d==0 then return {x=px-1,y=py} end --left
   if d==1 then return {x=px+1,y=py} end --right
   if d==2 then return {x=px,y=py+1} end --down
   return {x=px,y=py-1} --up
end

-- flags:
-- 0: collision
-- 1: cannot plant
-- 2: grab-able
-- 3: plowable
-- 4: plowed
-- 5: wet
--
function map_flag(x,y,f)
   return fget(mget(x,y),f) or
      fget(mget(x+32,y),f)
end

function map_flag_all(x,y,f)
   return fget(mget(x,y),f) and
      fget(mget(x+32,y),f)
end

function use_thing()
   local items=get_items()
   local item=items[item_sel]
   if item.fn != nil then
      local tgt=looking_at()
      item.fn(item, tgt.x, tgt.y)
   end
end

function animate(anim,done)
   animation=anim
   anim_done=done
   anim_index=1

   local frame=anim[1]
   anim_duration=frame.duration
end

function update_animation()
   if animation~=nil then
      anim_duration-=1
      if anim_duration==0 then
         anim_index+=1
         if anim_index>#animation then
            animation=nil
            anim_done()
         else
            local frame=animation[anim_index]
            anim_duration=frame.duration
         end
      end
   end
end

function collide(px,py,tx,ty)
   if tx~=px then
      if ty~=py then
         if map_flag(tx,ty,0) then return true end
      end
      if map_flag(tx,py,0) then return true end
   end
   if ty~=py then
      if map_flag(px,ty,0) then return true end
   end
   return false
end

buzz_time=0

function buzz()
   buzz_time=3
   sfx(0, 3)
end

is_sleeping = false
sleep_until = nil

function sleep_until_morning()
   d=2
   animate(
      {{frame=1,duration=15},
       {frame=13,duration=15},
       {frame=45,duration=15}},
      function()
         is_sleeping=true
         sleep_until=day+1
      end
   )
end

function update_time(inc)
   if buzz_time > 0 then
      buzz_time -= 0.75
   end

   if inc==nil then
      inc=hour_inc
   end
   hour+=inc
   if hour>=24 then
      day+=1
      hour-=24

      if day>=112 then
         day-=112
      end

      -- every night at midnight we
      -- dry everything out.
      for y=0,31 do
         for x=0,31 do
            local wet=mget(x,y)
            local dry=dry_map[wet]
            if dry~=nil then
               mset(x,y,dry)
            end
         end
      end
   end

   if is_sleeping and day == sleep_until and hour >= 8 then
      is_sleeping=false
      sleep_until=nil
      animate(
         {{frame=45, duration=15},
          {frame=13, duration=15},
          {frame=1,  duration=15}},
         function()
            save_game()
         end)
   end
end

function update_walk_impl()
   -- this is the core update fn
   -- of the game: what runs while
   -- you're "playing" the game.
   --
   -- most of the subsystems only
   -- update while you're playing,
   -- and are paused any other
   -- time (cutscenes, etc.)
   update_time()
   update_base()
   update_plants()
   penny:update()

   check_objective()

   if not is_sleeping and px==tx and py==ty then
      if btnp(⬅️) then
         if d~=0 then d=0 else tx=px-1 end
      end
      if btnp(➡️) then
         if d~=1 then d=1 else tx=px+1 end
      end
      if btnp(⬇️) then
         if d~=2 then d=2 else ty=py+1 end
      end
      if btnp(⬆️) then
         if d~=3 then d=3 else ty=py-1 end
      end
      if tx<1  then buzz() tx=1  end
      if tx>14 then buzz() tx=14 end
      if ty<1  then buzz() ty=1  end
      if ty>14 then buzz() ty=14 end
      if collide(px,py,tx,ty) then
         tx=flr(px) ty=flr(py)
      end
   end
   if px > tx then px -= spd end
   if px < tx then px += spd end
   if py > ty then py -= spd end
   if py < ty then py += spd end
   walking=not (tx == px and ty == py)
   if walking then
      energy_level-=walk_cost
      idle_time=0
   end

   if not walking then
      if btnp(❎) and
         grabbed_item==nil then
         open_item_menu()
      end
      if btnp(🅾️) then
         use_thing()
         idle_time=0
      end
   end

   if energy_level<=0 then
      -- uh oh, trouble.
      fade_out(function()
            px=base_x py=base_y d=2
            tx=px ty=py walking=false
            day+=1 hour=8
            energy_level=max_energy
            is_sleeping=false
            if chapter < 2 then
               do_script(cs_firstcharge)
            else
               do_script(cs_nobattery)
            end
      end)
   end

   idle_time+=0.0333
end

function update_walk()
   -- all the good stuff is in update_walk_impl but we have this
   -- stutter to make it easier to loop updates when sleeping or
   -- whatever.
   if is_sleeping then
      for _i=1,20 do
         update_walk_impl()
         if not is_sleeping then return end
      end
   else
      update_walk_impl()
   end
end

function update_menu()
   if btnp(⬇️) then menu_sel+=1 end
   if btnp(⬆️) then menu_sel-=1 end
   if btnp(❎) then menu_mode=false end
   if btnp(🅾️) then
      if menu_sel==#menu_items+1 then
         sleep_until_morning()
      else
         item_sel=menu_sel
      end
      menu_mode=false
   end
   menu_sel=mid(1,menu_sel,#menu_items+1)
   if not menu_mode then
      update_fn=update_walk
   end
end

update_fn=update_walk

function update_base()
   -- before penny fixes the base
   if (chapter < 2) return

   if px==base_x and py==base_y then
      energy_level=min(max_energy, energy_level+recharge_rate)
      if chapter >= 3 then
         tank_level=min(max_tank, tank_level+water_rate)
      end
   end
   end

function _update()
   update_animation()
   update_weather()

   --todo: this is kinda not how
   --we're doing this right now,
   --maybe we should modernize?
   if animation==nil then
      update_fn()
   end
end

function draw_box(x, y, w, h)
   palt(0, false)
   palt(12, true)
   spr(128,x,y)
   for ix=1,w do
      spr(129,x+(ix*8),y)
   end
   local xr = x+(w+1)*8
   spr(128,xr,y,1,1,true)
   for iy=1,h do
      spr(130,x, y+(iy*8),1,1,false)
      spr(130,xr,y+(iy*8),1,1,true)
   end
   local yb = y+(h+1)*8
   spr(128,x,yb,1,1,false,true)
   for ix=1,w do
      spr(129,x+(ix*8),yb,1,1,false,true)
   end
   spr(128,xr,yb,1,1,true,true)
   rectfill(x+8,y+8,xr,yb,0)
   palt()
end

function draw_menu(items, selection)
   local hght
   if chapter>1 then
      hght=4+#items
   else
      hght=1+#items
   end
   hght=max(hght,4)

   draw_box(64,0,6,hght)
   color(7)
   local lx=71
   local ly=9
   for i=1,#items do
      if selection == i then
         print(">",lx,ly)
      end
      if items[i].icon then
         spr(items[i].icon,lx+6,ly-1)
      else
         sspr(
            items[i].sx,items[i].sy,
            flower_size,flower_size,
            -- x+6,y-1 looks good for 8x8 sprites,
            -- for smaller flowers we need to adjust
            -- lx+6+4-...,ly-1+4-...
            lx+10-(flower_size/2),ly+3-(flower_size/2))
      end
      print(items[i].name,lx+16,ly)
      ly += 10
   end

   if chapter>1 then
      ly=10 + (hght - 1) * 8
      if selection==#items+1 then
         print(">",lx,ly)
      end
      spr(150,lx+6,ly-1)
      print("sleep",lx+16,ly)
   end
end

moon_phases={134,135,136,137,138,139,138,137,136,135}
function moon()
   -- 3 days in a phase
   -- 10 moon phases in a cycle
   local phase=flr(day/3)%10
   return {
      sprite=moon_phases[phase+1],
      flipped=phase>5
   }
end

function draw_time()
   -- daytime is 06:00-18:00
   -- night is 18:00-06:00
   -- where are we?
   local bg=12
   local fg=9
   local sp=133
   local fl=false

   local is_day=true
   local frc
   if hour>=6 and hour<18 then
      frc=(hour-6)/12
   elseif hour>=18 then
      frc=(hour-18)/12
      is_day=false
   else
      frc=(hour+6)/12
      is_day=false
   end

   if not is_day then
      local mun=moon()
      sp=mun.sprite
      fl=mun.flipped
      bg=0 fg=5
   end

   rectfill(16,2,110,11,bg)
   rect(16,2,110,11,fg)
   spr(sp,16+(87*frc),3,1,1,fl)
end

function draw_item()
   draw_box(96,104,2,1)
   print("🅾️",103,114,7)
   local items=get_items()
   if items[item_sel].icon then
      spr(items[item_sel].icon,112,112)
   else
      sspr(
         items[item_sel].sx,items[item_sel].sy,
         flower_size,flower_size,
         116-(flower_size/2),116-(flower_size/2))
   end
end

function draw_meters()
   draw_box(104,50,1,5)
   if tank_level>0 then
      local tank_frac=(max_tank-tank_level)/max_tank
      rectfill(111,57+41*tank_frac,115,98,12)
   end

   local nrg_frac=(max_energy-energy_level)/max_energy
   local nrg_color
   if nrg_frac<0.5 then
      nrg_color=11
   elseif nrg_frac<0.7 then
      nrg_color=10
   else
      nrg_color=8
   end
   rectfill(116,57+41*nrg_frac,120,98,nrg_color)
end

function world_to_screen(wx,wy)
   return {x=wx*8+4,y=wy*8+4}
end

function draw_map()
   local ofx=0
   local ofy=0
   if buzz_time>0 then
      ofy+=cos(buzz_time)
      ofx+=sin(buzz_time)
   end
   map( 0,0,ofx+0,ofy+0,16,16) -- base

   map(32,0,ofx+0,ofy+0,16,16) -- item
end

function draw_player()
   local idx=1
   local fl=false

   if animation~=nil then
      local frame=animation[anim_index]
      idx=frame.frame
   elseif grabbed_item~=nil then
      idx=35
   elseif is_sleeping then
      idx=45
      d=2
   else
      if (flr(time()*4)%2)==0 then
         idx+=2
      end
   end

   --if d==2 then fl=false end
   if     d==3 then idx+=8
   elseif d==1 then idx+=4
   elseif d==0 then idx+=4 fl=true
   end

   local sc=world_to_screen(px,py)

   local dx=0 local dy=-14
   if grabbed_item~=nil then
      if     d==0 then dx=-14
      elseif d==1 then dx=6
      elseif d==2 then dx=-4
      elseif d==3 then dx=-4
      end

      if d==3 then
         spr(
            grabbed_item,
            sc.x+dx,
            sc.y+dy,
            1,1)
      end
   end

   -- draw robo.
   palt(0, false)
   palt(12, true)
   spr(idx,sc.x-8,sc.y-12,2,2,fl)
   palt()

   if grabbed_item~=nil and
      d~=3 then
      spr(
         grabbed_item,
         sc.x+dx,
         sc.y+dy,
         1,1)
   end
end

function draw_base()
   local bsx=8*base_x
   local bsy=8*base_y

   if chapter < 2 or
      px~=base_x or
      py~=base_y then
      pal(10,6) -- no glow
   end

   spr(115,bsx-8,bsy)
   spr(115,bsx+8,bsy,1,1,true)
   spr(99,bsx-8,bsy-8)
   spr(99,bsx+8,bsy-8,1,1,true)
   circ(bsx-2,bsy-8,3,1)
   circfill(bsx-2,bsy-8,2,10)
   circ(bsx+9,bsy-8,3,1)
   circfill(bsx+9,bsy-8,2,10)

   pal()
end

function sort(ks,vs)
   local swapped=true
   while swapped do
      swapped=false
      for i=1,#ks-1 do
         if ks[i]>ks[i+1] then
            ks[i],ks[i+1]=ks[i+1],ks[i]
            vs[i],vs[i+1]=vs[i+1],vs[i]
            swapped=true
         end
      end
   end
end

function draw_objective()
   if objective then
      local t = "goal: "..objective
      color(0)
      print(t,1,122)
      print(t,3,122)
      print(t,2,121)
      print(t,2,123)
      print(t,2,122,7)
   end
end

function draw_debug()
   cursor(0,0,7)
   if px!=nil and py!=nil then
      print("x "..px.." y "..py.." t "..hour)
   end
   if chapter != nil then
      print("chapter: "..chapter)
   end
   if DBG_last_fail_msg != nil then
      print("last fail: "..DBG_last_fail_msg)
   end
   if penny.x!=nil then
      print("penny x "..penny.x.." y "..penny.y.." s "..penny.speed)
      print("      f "..penny.frame.." d "..penny.d)
      if penny._thread and costatus(penny._thread) ~= "dead" then
         if penny.DBG_thread_name then
            print("      act: "..penny.DBG_thread_name)
         else
            print("      act: ????")
         end
      end
   end
   for fi=1,#flowers do
      local f=flowers[fi]
      print(fi.." "..f.seed.name.." "..f.x.." "..f.y)
   end
   if DBG_last_ys then
      for yi=1,#DBG_last_ys do
         local ly=DBG_last_ys[yi]
         local la=DBG_last_draws[yi][2]
         if type(la)=="table" then
            la=la.seed.name
         end
         print(ly.." "..la)
      end
   end

   -- check the dumb clearing
   -- rect(px*8,py*8,(px+6)*8,(py+6)*8,10)
   -- if not _check_clear(px,py) then
   --    rect(
   --       DBG_clear_fail_pt[1]*8,
   --       DBG_clear_fail_pt[2]*8,
   --       DBG_clear_fail_pt[1]*8+8,
   --       DBG_clear_fail_pt[2]*8+8,
   --       7)
   -- end
end

-- the main rendering function
-- since almost everything is
-- always on the screen at the
-- same time.
function draw_game()
   -- first, we adjust the pals so
   -- that it looks like the right
   -- time of day. (but if we get
   -- here and the palette is
   -- already dark then just let it
   -- be.)
   if pal==original_pal then
      enable_sunshine(hour)
   end

   draw_map()

   -- make sure we draw the world
   -- objects in the right order.
   local draws={
      {draw_player,"robo"},
      {draw_base,"base"}
   }
   local ys={
      py*8+4,
      base_y*8+4
   }
   if penny.y~=nil then
      add(draws, {draw_penny,"pny"})
      add(ys, penny.y*8+4)
   end
   for f in all(flowers) do
      add(draws, {draw_flower,f})
      add(ys, f.y*8+4)
   end
   sort(ys,draws)
   -- DBG_last_ys=ys
   -- DBG_last_draws=draws
   for dd in all(draws) do
      dd[1](dd[2])
   end

   -- now rain and stuff
   draw_weather()

   -- now turn off the palettes so
   -- that the menu and stuff
   -- don't get affected by the
   -- time of day.
   disable_dark()

   -- hud and debug stuff
   if menu_mode then
      draw_menu(menu_items,menu_sel)
   elseif idle_time>1 then
      draw_item()
      draw_time()
      draw_meters()
      draw_objective()
   elseif (energy_level/max_energy)<0.25 then
      draw_meters()
   end

   -- draw_debug()
end

function _draw()
   -- dirty hack: if you set
   -- blank_screen to true then we
   -- won't bother drawing the
   -- game. (cut-scenes use this
   -- to do a blackout.)
   if blank_screen then
      cls(0)
   else
      draw_game()
   end

   -- the little box where people
   -- talk. (in 'cutscene stuff')
   draw_text()
end

-->8
-- water
function init_water()
   wet_map={}
   wet_map[64]=67
   wet_map[66]=68

   dry_map={}
   for k,v in pairs(wet_map) do
      dry_map[v]=k
   end
end

function i_water(item,tx,ty)
   if tank_level < 10 then
      DBG_last_fail_msg = "no water"
      buzz()
      return
   end

   if energy_level<water_cost then
      DBG_last_fail_msg = "no power"
      buzz()
      return
   end

   energy_level-=water_cost
   animate(
      {{frame=35,duration=10}},
      function()
         tank_level-=10
         local ground=mget(tx,ty)
         if wet_map[ground]~=nil then
            mset(tx,ty,wet_map[ground])
         end
   end)
end

-->8
-- plants and items

-- garbage_flower has the flower info.
#include garbage_flower.p8:1

grass={
   name="grass",
   rate=0.0006,
   stages={144,145,146,147}
}

plant_classes={grass}

flower_seeds={}

flowers={}
flower_size=6

function init_plants()
   -- init the reverse-lookup
   -- table for the plant data.
   local plant_spr={}
   for p in all(plant_classes) do
      for s in all(p.stages) do
         plant_spr[s]=p
      end
   end

   -- these are all the live
   -- plants
   plants={}
   for y=1,15 do
      for x=1,15 do
         local sp,age=mget(32+x,y),1
         local pl=plant_spr[sp]
         if pl~=nil then
            while pl.stages[age]~=sp do
               age+=1
            end
            age+=rnd()
            add(
               plants,
               {age=age,x=x,y=y,cls=pl})
         end
      end
   end
end

function update_plants()
   for p in all(plants) do
      local class=p.cls
      local age=p.age
      if age < #class.stages then
         -- update the age
         local new_age=age+class.rate
         if flr(new_age)~=flr(age) then
            mset(p.x+32,p.y,class.stages[flr(new_age)])
         end
         p.age=new_age
      end
   end

   for f in all(flowers) do
      if map_flag(f.x, f.y, 5) then
         -- :todo: cutscene for dry flower?
         f.age=min(f.age+flower_rate, 1)
      end
   end
end

function draw_flower(plant)
   -- OK we have an x and a y which are tile coords
   -- and a seed which is a flower{} object
   -- flower:draw() takes the bottom center location
   plant.seed:draw(4+plant.x*8, 8+plant.y*8, plant.age)
end

function remove_plant(x,y)
   for p in all(plants) do
      if p.x==x and p.y==y then
         del(plants,p)
         return
      end
   end
end

function add_plant(p,st,tx,ty)
   add(
      plants,
      {age=1,x=tx,y=ty,cls=p})
   mset(tx+32,ty,p.stages[st])
end

function i_plant(item,tx,ty)
   if map_flag(tx,ty,1) or
      energy_level < plant_cost or
      not map_flag(tx, tx, 4) then
      buzz()
      return
   end

   energy_level-=plant_cost
   local p=item.plant
   add_plant(p,1,tx,ty)
end

function remove_flower(x,y)
   for f in all(flowers) do
      if f.x==x and f.y==y then
         del(flowers,f)
         return
      end
   end
end

function add_flower(seed, age, tx, ty)
   add(flowers, {x=tx,y=ty,seed=seed,age=age})
   mset(tx+32,ty,148) -- add placeholder
end

function i_flower(item,tx,ty)
   if map_flag(tx,ty,1) or
      energy_level < plant_cost or
      not map_flag(tx, tx, 4) then
      buzz()
      return
   end

   energy_level-=plant_cost

   local seed=item.seed
   add_flower(seed, 0.25, tx, ty)
end


function i_grab(item,tx,ty)
   local tgt=mget(tx+32,ty)
   if grabbed_item~=nil then
      -- drop
      if fget(tgt,0) or
         tx < 0 or ty < 0 or
         tx > 15 or ty > 15 then
         -- nopers
         buzz()
      else
         mset(tx,ty,64) -- bare dirt
         mset(tx+32,ty,grabbed_item)
         remove_plant(tx,ty)
         remove_flower(tx,ty)
         grabbed_item=nil
      end
   elseif fget(tgt,2) then
      if energy_level>grab_cost then
         energy_level-=grab_cost
         grabbed_item=tgt
         mset(tx+32,ty,0)
      else
         buzz()
      end
   end
end

function i_till(item,tx,ty)
   -- check *plowable*
   if not map_flag_all(tx,ty,3) then
      buzz()
      return
   end

   if energy_level<plow_cost then
      buzz()
      return
   end

   energy_level-=plow_cost
   animate(
      {{frame=33, duration=5}},
      function()
         if mget(tx+32,ty)~=0 then
            remove_plant(tx,ty)
            remove_flower(tx,ty)
            mset(tx+32,ty,0) -- destroy
         end
         mset(tx,ty,66)    -- plowed
   end)
end

function init_items()
   item_sel=1
end

tl_grab={
   icon=142,name="grab",
   fn=i_grab}
tl_till={
   icon=141,name="till",
   fn=i_till}
tl_water={
   icon=143,name="water",
   fn=i_water}
tl_grass={
   icon=147,name="grass",
   fn=i_plant,plant=grass}

function get_items()
   local items
   if chapter < 3 then
      items = {tl_grab}
   else
      items = {
         tl_grab,tl_till,tl_water,
         tl_grass}

      for i=1,#flower_seeds do
          add(
             items,
             {sx=(i-1)*flower_size,sy=flower_sy,
              name=flower_seeds[i].name,fn=i_flower,
              seed=flower_seeds[i]})
      end
   end

   return items
end
-->8
-- weather
--
-- :todo: random weather on hour
-- and season.
function init_weather()
   raining=false
   rain={}
   max_rain=2000
end

function update_weather()
   -- todo: check the time, see if
   --       weather changes.

   if raining and #rain<max_rain then
      for i=1,rnd(40) do
         add(rain, {
                x=flr(rnd(128)),
                y=flr(rnd(128))-3,
                life=flr(rnd(10))
         })
      end
   end

   for drop in all(rain) do
      drop.y+=3
      drop.x+=1
      drop.life-=1
      if drop.y>=128
         or drop.life < 0 then
         del(rain,drop)
      end
   end
end

function draw_weather()
   for r in all(rain) do
      if r.life==0 then
         circ(r.x,r.y,1,12)
      else
         line(r.x,r.y-2,r.x+1,r.y,12)
      end
   end
end
-->8
-- fx
function init_fx()
   dark_levels={}
   for x=0,5 do
      local ramp={}
      for y=0,15 do
         ramp[y]=sget(x,y+40)
      end
      dark_levels[x]=ramp
   end
   original_pal=pal

   -- dark levels by hour.
   -- :todo: should also factor in phase of moon?
   local sm={}
   for i=0,4   do sm[i]=3    end
   for i=5,8   do sm[i]=8-i  end
   for i=9,16  do sm[i]=0    end
   for i=17,19 do sm[i]=i-16 end
   for i=20,24 do sm[i]=3    end
   sunshine_map=sm
end

function enable_sunshine(t)
   enable_dark(sunshine_map[flr(t)])
end

function enable_dark(d)
   --assert(pal==original_pal)
   dark_level=dark_levels[d]
   pal(dark_level)
   pal=fx_pal
end

function disable_dark()
   pal=original_pal
   pal()
end

function fx_pal(s,t,p)
   local lvl=dark_level
   local opal=original_pal
   if type(s)=="table" then
      for k,v in all(s) do
         opal(k,lvl[v],p)
      end
   elseif s==nil and t==nil then
      opal(lvl,p)
   else
      opal(s,lvl[t],p)
   end
end

function fade_out(fn)
   fade_t=5
   fade_lvl=sunshine_map[flr(hour)]
   update_fn=update_fade
   fade_cb=fn
end

function update_fade()
   enable_dark(fade_lvl)
   fade_t-=1
   if fade_t<=0 then
      fade_lvl+=1
      if fade_lvl>5 then
         disable_dark()
         resume(fade_cb)
      else
         fade_t=5
      end
   end
end

--[[
   function dump_darkness()
   pal()
   for ilvl=1,#dark_levels do
   local lvl=dark_levels[ilvl]
   for ic=1,#lvl do
   local y=(ilvl-1)*4
   local x=(ic-1)*4
   rectfill(x,y,x+3,y+3,lvl[ic])
   end
   end
   end
]]

function dump_obj(o)
   local t = type(o)
   if o == nil then
      return "nil"
   elseif t == "table" then
      local r = "{"
      local first_item=true
      for i=1,#o do
         if not first_item then
            r=r..", "
         end
         r=r..dump_obj(o[i])
         first_item=false
      end
      for k,v in pairs(o) do
         if type(k)~="number" or k<1 or k>#o then
            if not first_item then
               r=r..", "
            end
            r=r..dump_obj(k).."="..dump_obj(v)
            first_item=false
         end
      end
      r = r.."}"
      return r
   elseif t == "number" then
      return tostr(o)
   elseif t == "string" then
      return "'"..o.."'"
   elseif t == "thread" then
      return "coro"
   elseif t == "function" then
      return "function"
   else
      return "?? ("..t..")"
   end
end

-->8
-- cutscene stuff

-- portraits
--  py_ear_up=194
--  py_ear_mid=192
--  py_ear_down=196
--  py_head_wry=224
--  py_head_talk=226
--  py_head_closed=228
--  py_head_intense=230
py_mid_wry={top=192,bot=224}
py_mid_talk={top=192,bot=226}
py_mid_closed={top=192,bot=228}
py_up_talk={top=194,bot=226}
py_up_closed={top=194,bot=228}
py_up_intense={top=194,bot=230}
py_down_wry={top=196,bot=224}

-- cutscenes.
cs_intro={
   {
      pre=function()
         cls(0)
         penny:show(base_x,base_y+2,0)
         blank_screen=true
      end,
      "Penny?",
      "PENNY!",
      "...",
      "Where is that girl?"
   },

   {
      p=py_mid_closed,
      "OK...\nDeep breath..."
   },

   {
      p=py_up_intense,
      "RX-228! Activate!!!"
   },

   {
      pre=function()
         blank_screen=false
      end,
      p=py_up_talk,
      "It... it works?",
      "It works!"
   },

   {
      "PENNY? WHERE ARE\nYOU??"
   },

   {
      pre=function()
         penny:show(penny.x,penny.y,2)
      end,
      p=py_up_intense,
      "COMING MOM!"
   },

   {
      pre=function()
         penny:show(penny.x,penny.y,0)
      end,
      p=py_mid_wry,
      "OK. That's enough\nfor today.",
      "You sit tight.",
      "I'll be back soon to\nfinish up."
   },

   post=function()
      energy_level = max_energy/4
      tank_level = 0
      penny:start_leave()
      update_fn = update_walk
      chapter = 1
   end
}

function start_ch2()
   penny:start_wander()
   update_fn=update_walk
   objective="clear a 6x6 field"
   objective_fn=check_bigspace
end

cs_firstcharge={
   {
      pre=function()
         cls(0)
         penny:show(base_x,base_y+2,0)
         blank_screen = true

         -- ♪: set the chapter early
         --     so the base glows.
         chapter = 2
      end,
      "...",
      "Hey... how'd you get\nover there?",
      "Oof...",
      "There you go!"
   },

   {
      pre=function()
         blank_screen=false
      end,
      p=py_mid_wry,
      "Huh...",
      "I guess you really\nDO work!"
   },

   {
      p=py_up_intense,
      "Ha! I knew it!",
      "I AM THE BEST!"
   },

   {
      p=py_mid_talk,
      "Well, I've finished\nthis base.",
      "If you stand there,\nyou'll recharge."
   },

   {
      p=py_mid_wry,
      "Try not to run out\nof power, ok?"
   },

   {
      "PENNY!",
      "THAT FIELD CLEAR\nYET?"
   },

   {
      p=py_mid_wry,
      "Oh, uh...",
      "Hey, help me clear\nthis field?",
      "Mom wants a big\nclear space..."
   },

   {
      p=py_down_wry,
      "...but these rocks\nare so big."
   },

   {
      p=py_up_talk,
      "Help me move these,\nOK?"
   },

   post=start_ch2
}

function _check_clear(x,y)
   for iy=0,5 do
      for ix=0,5 do
         if map_flag(x+ix,y+iy,0) then
            DBG_clear_fail_pt={x+ix,y+iy}
            return false
         end
      end
   end

   DBG_clear_fail_pt=nil
   return true
end


function check_bigspace()
   DBG_last_fail_msg=nil

   if not penny:visible() then
      DBG_last_fail_msg="penny gone"
      return
   end

   if grabbed_item then
      DBG_last_fail_msg="holding something"
      return
   end

   for y=1,9 do
      for x=1,9 do
         if _check_clear(x,y) then
            objective=nil
            objective_fn=nil
            do_script(cs_didclear)
            return
         end
      end
   end
   DBG_last_fail_msg="no big space"
end

function start_ch3()
   chapter = 3
   tank_level = max_tank
   penny:start_leave()
   update_fn = update_walk
end

cs_didclear={
   {
      pre=function()
         penny:face(px, py)
      end,
      p=py_up_talk,
      "Hey!\nYou did it!",
      "Looks great!"
   },

   {
      p=py_mid_talk,
      "Wait a bit, I'll be\nback!"
   },

   {
      pre=function()
         local ox = penny.x
         penny:leave()

         -- :todo: a little bit between when she leaves and when
         --        she comes back?

         penny:show(16, py+2, 2)
         penny:run_to(px*8+4, penny.y)
         penny:show(penny.x, penny.y, 0)
      end,

      p=py_mid_wry,
      "Now, don't move, OK?",
      "Just gonna open you\nup..."
   },

   {
      pre=function()
         d=2 -- look down (face penny)
         for i=1,2 do
            sfx(1, 3) -- tool sound
            yield()
            while stat(49)>=0 do
               yield()
            end
         end
      end,
      p=py_mid_talk,
      "Done!",
      "Ok, check it out.\nTools!",
      "I've given you some\nuseful stuff.",
      "You've got a\nwatering can...",
      "...and this neat\nlittle plow...",
      "...and then this seed\npouch!"
   },

   {
      p=py_mid_wry,
      "Press 🅾️ to open the\nmenu to see."
   },

   {
      "PENNY!",
      "YOU LEFT THE DOOR OPEN AGAIN!"
   },

   {
      p=py_down_wry,
      "Whoops....",
      "She sounds mad.",
      "Maybe some flowers will\ncheer her up...",
      "Can you get me 3\n$1 flowers?"
   },

   post=start_ch3
}

--
local old_penny_visible=false

cs_nobattery={
   {
      pre=function()
         old_penny_visible = penny:visible()

         cls(0)
         penny:show(base_x, base_y+2, 0)
         blank_screen=true
      end,

      "Robo?\nCan you hear me?"
   },

   {
      pre=function()
         blank_screen=false
      end,
      p=py_mid_wry,
      "Oh, thank goodness."
   },

   {
      p=py_up_closed,
      "Robo, you need to be\nmore careful!",
      "If you don't charge,\nyou'll get stuck!"
   },

   {
      p=py_mid_wry,
      "Don't worry.",
      "I'll always be there\nto help."
   },

   post=function()
      if not old_penny_visible then
         penny:leave()
      end
      update_fn=update_walk
   end
}

--

function check_objective()
   if objective_fn then
      objective_fn()
   end
end

function resume(cb)
   local cbt=type(cb)
   if cbt=="function" then
      cb()
   elseif cbt=="thread" then
      assert(coresume(cb))
   end
end

local script_coro = nil

function update_script()
   idle_time = 0
   assert(coresume(script_coro))
end

function do_script(script)
   script_coro = cocreate(function()
         local skipping=false
         local stage,s_line
         for stage in all(script) do
            if stage.pre then
               stage.pre()
            end
            local p=stage.p or {}
            for s_line in all(stage) do
               if not skipping then
                  skipping = show_text(s_line, p.top, p.bot, _coro)
               end
            end
         end
         if script.post then
            script:post()
         end
   end)
   update_fn=update_script
end

local text
local skip_time

function init_text()
   text = nil
   skip_time = 0
end

function show_text(t, top, bot, coro)
   text = t
   text_time = 0
   text_limit = #text + 5
   text_sprite_top = top
   text_sprite_bot = bot

   while not btnp(🅾️) do
      if btn(❎) then
         skip_time += 0.03
      else
         skip_time = 0
      end
      if skip_time >= 1 then
         yield()
         text = nil
         return true
      end
      text_time = min(text_limit, text_time + 2)
      yield()
   end

   -- gotta go back to update to clear the btnp,
   -- otherwise every other time we call btnp()
   -- it will still return true. (We're in game
   -- time here not frame time!)
   yield()

   text = nil
   return false
end

function draw_arc(x,y,radius,angle)
   -- just figure out how far around
   local h = -sin(mid(0,angle,0.5) / 2) * radius * 2
   local px,py,pw,ph = clip(x, y-radius, radius+1, h+2)
   circ(x, y, radius)
   if angle > 0.5 then
      angle -= 0.5
      local top = (y + radius) + (radius * 2 * sin(mid(0,angle,0.5) / 2))
      clip(x-radius, top, radius+1, y+radius-top+2)
      circ(x, y, radius)
   end

   clip(px,py,pw,ph)
end

function draw_text()
   if (text==nil) then
      return
   end

   -- outline box
   draw_box(0,96,14,2)

   -- actual text
   local ss=sub(text,1,1+text_time)
   if sub(ss,-1,-1)=="^" then
      ss=sub(ss,1,-2)
   end
   draw_string(
      ss,
      28,114-11,7)

   color(7)
   if skip_time > 0 then
      draw_arc(128-16+3, 128-14+2, 4, skip_time)
   elseif text_time==text_limit and
      time()%2>1 then
       print("🅾️",128-16,128-14)
     end

   -- portrait
   if text_sprite_top~=nil then
      spr(text_sprite_top,8,114-24,2,2)
      spr(text_sprite_bot,8,114-8,2,2)
   end
end

penny = {
   x=nil, y=nil, d=0,
   speed=0.09,
   frame=0,
   _thread=nil
}

function penny:draw()
   if self.x ~= nil then
      local f,sy,sh,sx,sw=false,32,16
      if self.d==0 or self.d==2 then
         sx,sw=72,10
         if self.d==2 then
            sy+=sh
         end
         if self.frame>=1 then
            sx+=sw
         end
      else
         if self.frame<1 then
            sx,sw=92,12
         else
            sx,sw=105,18
         end
         if self.d==-1 then
            f=true
         end
      end

      palt(0, false)
      palt(12, true)
      sspr(
         sx,sy,sw,sh,
         self.x*8,---(sw/2),
         self.y*8-16,
         sw,sh,
         f)
      palt()
   end
end

function draw_penny()
   penny:draw()
end

function penny:update()
   if self._thread and costatus(self._thread) ~= "dead" then
      assert(coresume(self._thread))
   end
end

function penny:face(tx, ty)
   local dx = tx - self.x
   local dy = ty - self.y

   local direction
   if abs(dx) > abs(dy) then
      if dx > 0 then
         direction = 1
      else
         direction = -1
      end
   else
      if dy > 0 then
         direction = 2
      else
         direction = 0
      end
   end
   self.d = direction
   self.frame = 0
end

function penny:run_to(tx, ty)
   self:face(tx, ty)
   local direction = self.d

   local atime, t = 0, 0
   while self.x != tx or self.y != ty do
      t += self.speed
      atime += self.speed
      while atime >= 1 do
         atime -= 1
      end

      local ox,oy=self.x,self.y
      local dist = (sin(t) + 1) * 0.375
      local dx,dy=tx-self.x,ty-self.y
      local dlen=dist / sqrt(dx*dx+dy*dy)
      dx *= dlen dy *= dlen
      self.x = mid(self.x, self.x+dx, tx)
      self.y = mid(self.y, self.y+dy, ty)

      self.frame = flr(atime * 2) * 2
      yield()
   end
   self.frame = 0
end

function penny:leave()
   if self.y ~= nil then
      self:run_to(16, self.y)
   end
end

function penny:sleep_until(until_hour)
   while until_hour < hour do
      yield()
   end
   while hour < until_hour do
      yield()
   end
end

function penny:wander_around()
   while hour >= 8 and hour <= 18 do
      local dst = flr(rnd(16))
      local tx, ty = self.x, self.y
      if rnd() >= 0.5 then
         tx=dst
      else
         ty=dst
      end
      tx = mid(8,tx,111)
      ty = mid(8,ty,111)

      self:run_to(tx, ty)

      local t=(rnd()*30)+10
      while t>0 do
         t -= 1
         yield()
      end
   end
end

function penny:start_wander()
   self.DBG_thread_name = "start_wander"
   self._thread = cocreate(function()
         while true do
            -- Wander around the field until...
            self:wander_around()

            -- oh no, it's late! Penny, run home!
            local old_x = self.x
            self:leave()

            -- sleep until the morning.
            self:sleep_until(8)

            -- come back to the field
            self:run_to(old_x, self.y)
         end
   end)
end

function penny:start_leave()
   self.DBG_thread_name = "start_leave"
   self._thread = cocreate(function()
         penny:leave()
   end)
end

function penny:show(x,y,d)
   self.x=x self.y=y self.d=d
   self.frame = 0
end

function penny:visible()
   return self.x ~= nil and self.y ~= nil and
      self.x >= 0 and self.x < 16 and
      self.y >= 0 and self.y < 16
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
font_enc=[[414869999f994248caae999e4348699889964448e999999e4548f88e888f4648f88e888847486998b9964848999f99994918ff4a48111111964b48999e99994c488888888f4d58dd6b18c6314e489ddbb9994f48699999965048e99e8888515864a5295a4d5248e99e99995348698611965438e9249255489999999656588c6315294457588c6318d6aa58588a9442295159588c62a210845a48f122448f615564a52680624788e999606345698960644711799960654569f8706647254e444067456971e0684788e999906917be6a47101119606b478899e9906c27aaa46d55556b18806e45ad99906f456999607045699e8071456997107245ad988073457861e074374ba490754599996076558c54a20077558c6b550078558a88a88079459971e07a45f168f03048699bd996313859249732486911248f3348691211963448aaaf22223548f88e11963648698e99963748f11248883848699699963948699711112118fd3f5874622210042e11803a16902c2358272858002d44f00028382a491129388892548e767d8f5e37c00097767dafbeb7c000]]

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
         assert(glyph~=nil, "char "..chr(c).." not in font")
         draw_font_glyph(glyph,lx,ly)
         lx+=glyph.w+1
      end
   end
end
__gfx__
0000000000cccccccccccc0000cccccccccccc00ccc0ccccccccccccccc0cccccccccccc00cccccccccccc0000cccccccccccc0000cccccccccccc0000000000
00000000070c00000000c070070c00000000c07000070c00000ccccc00070c00000ccccc070c00000000c070070c00000000c070070c00000000c07000000000
00700700c07007777770070cc07007777770070c070700e007700ccc070700e007700cccc07007777770070cc07007777770070cc07007777770070c00000000
00077000cc007000000700cccc007000000700ccc0700ee0000770ccc0700ee0000770cccc070000000070cccc070000000070cccc007000000700cc00000000
00077000c00000000000000cc00000000000000ccc00eee00000770ccc00eee00000770cc00070000007000cc00070000007000cc00000000000000c00000000
007007000e7000e00e0007e00ee000e00e000ee0cc0ee00e0000070ccc0ee00e0000070c077007000070077007700700007007700e700000000007e000000000
000000000e7000e00e0007e00ee000e00e000ee0cc0e0770e000070ccc0e0770e000070c077000777700077007700077770007700e7000e00e0007e000000000
000000000ee0000000000ee00ee0000000000ee0cc0070070000070ccc0070070000070c077000700700077007700070070007700ee0000000000ee000000000
c00cc00c0ee0770000770ee00ee0770000770ee0cc0e0070e700000ccc0e0070e700000c0ee0700000070ee00ee0700000070ee00ee0770000770ee000000000
0ee00ee000007777777700000000777777770000cc0ee070e770000ccc0ee070e770000c000070eeee070000000070eeee070000000077777777000000000000
0e0ee0e000007777777700000ee0777777770ee0cc0ee070e777770ccc0ee0700777770c0ee0e0eeee0e0ee00000e0eeee0e0000000077777777000000000000
0e0e5e0007707777777707700000777777770000cc0ee070e777770ccc0ee0070007770c0000ee0000ee00000ee0ee0000ee0ee0077077777777077000000000
0e05e0cc0ee0077777700ee00ee0077777700ee0ccc00777077770ccccc00000770070cc0ee00eeeeee00ee00ee00eeeeee00ee00ee0077777700ee000000000
c000000c0ee0000000000ee00ee0000000000ee0cc00777700000ccccc00000777700ccc0ee0000000000ee00ee0000000000ee00ee0000000000ee000000000
0ee0eee0c000eee00eee000c0ee0e00ee00e0ee0cc0070070e0e0ccccc0e000700700ccc0ee0e00ee00e0ee0c000eee00eee000cc000eee00eee000c00000000
00000000ccc0000000000cccc00000000000000ccc000c0000000ccccc000c0000000cccc00000000000000cccc0000000000cccccc0000000000ccc00000000
c00cc00c00cccccccccccc0000cccccccccccc00ccc0ccccccccccccccc0cccccccc000000cccccccccccc0000cccc0000cccc0000cccccccccccc0000000000
0ee00ee0070c00000000c070070c00000000c07000070c00000ccccc00070c0000000770070c00000000c070070c00000000c070070c00000000c07000000000
0e0ee0e0c07007777770070cc07007777770070c070700e007700ccc070700e00077070cc07007777770070cc07007777770070cc07007777770070c00000000
0e0e5e00cc007000000700cccc007000000700ccc0700ee0000770ccc0700ee007700770cc070000000070cccc070000000070cccc007000000700cc00000000
00e5e0ccccc0000000000cccc00000700700000ccc00eee00000770ccc00ee0077000000ccc0700000070cccc00070000007000cc00000000000000c00000000
c000000cccc000e00e000ccc0e7007e00e7007e0cc0ee00e0000070ccc0ee0077000070cccc0070000700ccc07700700007007700e700000000007e000000000
0eee0ee0c00000e00e00000c0e70eee00eee07e0cc0e0770e000070ccc0e00770000070cc00000777700000c07700077770007700e700000000007e000000000
000000000e700000000007e0c000ee0000ee000ccc0070000000070ccc0070000000070c077000700700077007700070070007700ee0000000000ee000000000
000000000e707000000707e0cc000000000000cccc0e00770000000ccc0e07707000000c07707000000707700ee0700000070ee00ee0770000770ee000000000
000000000ee0777777770ee0ccc0777777770ccccc0ee0077000000ccc0ee00e7700000c077070eeee070770c00070eeee07000c000077777777000000000000
000000000ee0077777700ee0ccc0777777770ccccc0eee007700770ccc0eeeee7777770c0ee0e0eeee0e0ee0ccc0e0eeee0e0ccc000077777777000000000000
00000000c00000777700000cccc0777777770ccccc0eeee007700000cc0eeeee7777770c0000ee0000ee0000ccc0ee0000ee0ccc077077777777077000000000
00000000cc00e700007e00ccccc0077777700cccccc0000e00770770ccc0000e777770ccc0000eeeeee0000cccc00eeeeee00ccc0ee0077777700ee000000000
00000000ccc0ee7007ee0cccccc0000000000ccccc0000000000070ccc00000000000ccccc000000000000ccccc0000000000ccc0ee0000000000ee000000000
00000000ccc00ee00ee00cccccc0eee00eee0ccccc0e0c0e0e0e0770cc0e0c0e0e0e0cccccc0e00ee00e0cccccc0eee00eee0cccc000eee00eee000c00000000
00000000ccc0000000000cccccc0000000000ccccc000c0000000000cc000c0000000cccccc0000000000cccccc0000000000cccccc0000000000ccc00000000
444444440566660054454445555555551551555100000000000000000000000000000000cc11cc11cc1f111111f1cccccccccccccccccccccccccccccccccccc
454444446655566045445454515555555155151500000000000000000000000000000000c1ff11ff1c1f1ffff1f1ccccc11ccccccccccccccccccccccccccccc
4444454466656666454544545555515551515515000000000000000000000000000000001fff11fff11f1feef1f1cccc1fe1cccccccccc11111ccccccccccccc
4444444466556666544544455555555515515551000000000000000000000000000000001fff11fff1c17dffd71ccccc1fe1ccccccccc1eeeee1cccccccccccc
4444444455665565454454545555555551551515000000000000000000000000000000001fff11fff11ff7ff7ff1cccc1ffe1cccccccc1fffffe11111ccccccc
4444544466656565454544545555155551515515000000000000000000000000000000001fff11fff11fdffffdf1ccccc1ff1ccccccccc1111fffff7f1cccccc
445444440655665054454445551555551551555100000000000000000000000000000000c1ff11ff1c1fdffffdf1cccccc1f11ccccc1111111111f7dfe1ccccc
444444440055550045445454555555555155151500000000000000000000000000000000c1ffffff1c1fdffffdf1ccccc1ff7f1ccc177fffff111fffff1ccccc
0000000000000000000000004444444400000000000000000000000000000000000000001ffffffff11ffffffff1ccccc1f7dfe1cc177ffffffffffff1cccccc
1110001111000000000000004444444400000000000000000000000000000000000000001ffffffff11ffffffff1cccc11fffff1ccc1fffffffffff11ccccccc
2211002521100000000000004444444400000000000000000000000000000000000000001ffffffff1c1ff77ff1cc111ffffff1ccc1ffffffffffff11ccccccc
333110333311000000000000444444440000000000000000000000000000000000000000c11ffff11cc1f7777f1c177ffffff1ccc1fff111111ffffff1cccccc
4221102d4422100000000000444444440000000000000000000000000000000000000000c1ffffff1cc1f1771f1c177ffffff1cccc111cccccc111111ccccccc
5511105555110000000000004445544400000000000000000000000000000000000000001fff77fff11ff1111ff11ffffefff1cccccccccccccccccccccccccc
66d5106666dd5100000000004445544400000000000000000000000000000000000000001ff7777ff11ff1cc1ff11fffffefff1ccccccccccccccccccccccccc
776d1077776dd55000000000444444440000000000000000000000000000000000000000c11111111c1f1cccc1f1c111111111cccccccccccccccccccccccccc
88221018888221000000000000000000cccccccccccccccccccccccccccccccc00000000cc11cc11cc1f1cccc1f1cccccccccccccccccccccccccccccccccccc
9422104c999421000000000000000000cccccccccccccccccccccccccccccccc00000000c1ff11ff1c1ff1cc1ff1cccccccccccccccccccccccccccccccccccc
a9421047aa9942100000000000000111cccc00cccccccccccccccccccccccccc000000001fef11fef11ff1111ff1cccccccccccccccccccccccccccccccccccc
bb3310bbbbb3310000000000000001a1ccc0bb0ccccccccccccccccccccccccc000000001fef11fef1c1f1771f1ccccccccccccccccccccccccccccccccccccc
ccd510ccccdd51100000000000001161cc0bbbb0cccccccccccccccccccccccc000000001fef11fef1c1f7777f1ccccccccccccccccccccccccccccccccccccc
d55110dddd5110000000000000001aa1c0bb00bb0ccccccccccccccccccccccc000000001fef11fef1c1ff77ff1ccccccccccccccccccccccccccccccccccccc
ee82101eee8822100000000000111661c03b0c0b0ccccccccccccccccccccccc00000000c1ff11ff1cc1ffffff1ccccccccccccccccccccccccccccccccccccc
f94210f7fff9421000000000001aaaa1cc0bb0c0cccccccccccccccccccccccc00000000c1ffffff1c1ffffffff1cccccccccccccccccccccccccccccccccccc
00000000000000006666666600116661c003b0cccccccccccccccccccccccccc000000001ff7ff7ff11feffffef1cccccccccccccccccccccccccccccccccccc
0000000000000000666666660001aaa10bb0bb0ccccccccccccc00c00ccccccc000000001f7dffd7f11feffffef1cccccccccccccccccccccccccccccccccccc
000000000000000066566566011166613bbbbb0cccccccccccc0bb03b0c00ccc000000001fffeefff11feffffef1cccccccccccccccccccccccccccccccccccc
00000000000000006656656601aaaaa103330b0cccccccccccc033bbb00bb0cc00000000c11ffff11cc1f7ff7f1ccccccccccccccccccccccccccccccccccccc
00000000000000006656656601166661c00003b0cccccccccccc003bb0b330cc00000000c1ffffff1c1f7dffd7f1cccccccccccccccccccccccccccccccccccc
000000000000000066566566001aaaa1ccccc03b0ccccccccccccc03bb300ccc000000001ffeffeff11f1feef1f1cccccccccccccccccccccccccccccccccccc
00000000000000006656656611166661cccccc03b0cccccccccccc03b00ccccc000000001ffeffeff11f1ffff1f1cccccccccccccccccccccccccccccccccccc
0000000000000000666666661aaaaaa1cccccc03b0cccccccccccc03b0cccccc00000000c11111111c1f111111f1cccccccccccccccccccccccccccccccccccc
cccccccccccccccccc53350000000500000000000000000000555500005555000055550000555500000000000055550066555500665555000006666000076000
cccccccccccccccccc53350000000050000005000990909005777750057777500577755005777550057755500555555056677750566777500067777607666660
cccc555555555555cc53350000000505000033500099999057777775577777555777755557775555577555555555555505667765056677656677666600000000
ccc5533333333333cc5335000000500000099335099aa9005777777557777775577775555777555557755555555555555756566557565665777655550c0c0c00
cc55333333333333cc5335000005000000998053009aa99057777775577777755777755557775555577555555555555557755665577556657776000000000000
cc53335555555555cc53350006650000099800300999990057777775577777555777755557775555577555555555555557766665544666456677666600c0c0c0
cc53350000000000cc53350067650000998000000909099005777750057777500577755005777550057755500555555005666650445464540067777600000000
cc53350000000000cc5335007650000098000000000000000055550000555500005555000055550000555500005555000055550045444444000666600c0c0c00
000000000000000000000000b0000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000003b00b3bb000000000000000000000077000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000b0b00b0b3b30000000000000000000077007000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000b0b0003b30b30000000000000000077007070000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000b0000b30b00b0b3b300000000000000000007070077000000000000000000000000000000000000000000000000000000000000000000000000
000000000b000b00b0b30b00b0b3b30b000330000000000070077000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b0000b300b300b300bb00bb3b3b0000330000000000077000000000000000000000000000000000000000000000000000000000000000000000000000000
00b0b0bb03b0b3b00b30b3b00bb3b3b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05666600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66555660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66656666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66556666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55665565000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66656565000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06556650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06600060006600060066600060600660666000660066600660666066006060666066000066600600660000666060000600606066606600066006000000000000
06060606006060606006000060606000600000606060006000600060606060600060600060006060606000600060006060606060006060600006000606000006
06060606006060606006000060606660660000660066006660660066006060660060600066006060660000660060006060606066006600666006006606600066
06060606006060606006000060600060600000606060000060600060606060600060600060006060606000600060006060666060006060006000066000660660
06600060006060060006000006606600666000606066606600666060600600666066000060000600606000600066600600666066606060660006000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06666666006666666666600066666666666000666666666666666666666666666666600066666666666000666666666666666666666666666666000000000000
0000000000000ff00ff0000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000fef00fef00000000fef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000feeeffeeef000000feeef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000ffff000feeeeffeeeef0000feeeef000ffff000fff00000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffffff00feeeeffeeeef0000feeeef00ffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffef0feeeeeffeeeeef00feeeeefffffffef0fffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
fffffeef0feeeeeffeeeeef00feeeeeffffffeef0fefffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
fffffeef0feeeef00feeeeef0feeeef0fffffeef0feeffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeeef00feeeeef0feeeef0ffffeeef0feeffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ff0feeef0feeef0000feeeef0feeef00ff0feeef0feeeff000000000000000000000000000000000000000000000000000000000000000000000000000000000
f00feeef0feef000000feeef0feef000f00feeef0feef00000000000000000000000000000000000000000000000000000000000000000000000000000000000
000feeef0feef000000feeef0feef000000feeef0feef00000000000000000000000000000000000000000000000000000000000000000000000000000000000
000feffffffef000000feffffffef000000feffffffef000000feffffffef0000000000000000000000000000000000000000000000000000000000000000000
000ffffffffff000000ffffffffff000000ffffffffff000000ffffffffff0000000000000000000000000000000000000000000000000000000000000000000
00ffffffffffff0000ffffffffffff0000ffffffffffff0000ffffffffffff000000000000000000000000000000000000000000000000000000000000000000
00fffeffffefff0000ffffffffffff0000ffffffffffff0000ffffffffffff000000000000000000000000000000000000000000000000000000000000000000
0ffeeffffffeeff00fffeeffffeefff00ffeeffffffeeff00ffeeffffffeeff00000000000000000000000000000000000000000000000000000000000000000
0feffffffffffef00ffeffffffffeff00ffffeffffeffff00ffffeffffeffff00000000000000000000000000000000000000000000000000000000000000000
0fff77ffff77fff00fff77ffff77fff00ffffffffffffff00fff77ffff77fff00000000000000000000000000000000000000000000000000000000000000000
fff7ddffffdd7ffffff7ddffffdd7ffffffeffffffffeffffff7ddffffdd7fff0000000000000000000000000000000000000000000000000000000000000000
fff7ddffffdd7ffffff7ddffffdd7fffffffeeffffeefffffff7ddffffdd7fff0000000000000000000000000000000000000000000000000000000000000000
fffffffffffffffffffffffeeffffffffffffffeeffffffffffffffeefffffff0000000000000000000000000000000000000000000000000000000000000000
ffffffeeeeffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
fffffffeefffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000
fffffeffffffffffffffffe77effffffffffffffffffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
ffffffeeffffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
00ffffffffffff0000fffffeefffff0000ffffffffffff0000fffffeefffff000000000000000000000000000000000000000000000000000000000000000000
__gff__
0800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008071828380000000000000000000000000000030000000000000000000000000000000300000000000000000000000000000203000000000000000000000000
000000000000000000000000000000000a0a0a0a0a0000000000000000000000070a0a0a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404042000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404042000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
050100000c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c760107600c76010760
5e0500002b2512b2512b2512b2502b2503f2013f2013f2013f201000003f2503f2503f2513f2513f2513f2513f25100000000003520135201352013f2513f2513f2513f2513f2503f2503f2503f2003f2003f200
