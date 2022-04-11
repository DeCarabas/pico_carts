pico-8 cartridge // http://www.pico-8.com
version 35
__lua__
-- robo gardening game
-- (c) 2020-2022 john doty
--
-- To Release:
--
-- $ cat robo.p8 | sed 's/--.*//g' | sed '/^[ ]*$/d' > robo_release.p8
--
-- :todo: what is 6x6?
-- :todo: victory tune when cleared (a ping?)
-- :todo: trees
-- :todo: fix transition walking in
-- :todo: weather through the window
-- :todo: weather sound indoors
-- :todo: birds singing at night?
-- :todo: call penny to you
-- :todo: treasure
-- :todo: logs

-- the base object for the cutscene system
script={}

-- the pico-8  map is 128x32

-- that's two maps tall and eight maps wide
-- currently we use the first two maps in the top row as
-- base layers in a map, and the bottom two maps in the
-- row as item layers. we might use other maps as necessary.

-- in theory we can do so much here but we have to be able
-- to save our game in 256 bytes and there's only so much we
-- can throw away when we load

-- fetch the item for the tile (off of the item layer)
function get_item(x,y)
   return mget(x,y+16)
end

-- set the item for the tile (onto the item layer)
function set_item(x,y,i)
   return mset(x,y+16,i)
end

-- place a random number of the given sp on the item layer
function place_rand(count, sp)
  while count>0 do
    local x,y=rnd_int(16),rnd_int(16)
    if not map_flag(x,y,1) then
      set_item(x,y,sp)
      count-=1
    end
  end
end

function all_map(fn)
  for y=0,15 do for x=0,15 do
      fn(x,y,get_item(x,y))
  end end
end

-- game progress
--  chapter 0: pre-intro
--  chapter 1: walking/no charge
--  chapter 2: walk outside
--  chapter 3: clear field
--  chapter 4: till and plant
function new_game()
  chapter=0
  day=0
  hour=8
  px=base_x
  py=base_y
  grabbed_item=nil
  log_count=0

  trees={}
  flower_pockets={}
  flowers={}
  flower_seeds={}

  -- init the item sprite layer
  place_rand(20,144) --grass
  place_rand(20,145) --grass
  place_rand(20,146) --grass
  place_rand(20,147) --grass
  place_rand(30,149) --stump/tree
  place_rand(40,160) --rock

  for x=5,10 do       -- clear the front door
    for y=1,4 do
      set_item(x,y,0)
    end
  end

  for fi=0,15 do
    add(flower_seeds, flower:new(flower_size,fi))
  end

  all_map(function(x,y,sp)
      if sp==149 then
        add_tree(x,y,rnd{206,238})
      end
  end)
end

stream={}
function stream:new(address,limit)
   return setmetatable(
      {buffer=0,write_bits=8,read_bits=0,address=address,limit=limit},
      {__index=self})
end
function stream:read()
  --assert(self.limit > 0)
  self.limit-=1
  self.address+=1

  return @(self.address-1)
end
function stream:read2()
  --assert(self.limit > 1)
  self.limit-=2
  self.address+=2
  return %(self.address-2)
end
function stream:unpack(width, count)
  local buffer,bits,ret,result,lw = self.buffer,self.read_bits,{}

  for ii=1,count do
    result = 0 lw = width
    while lw > 0 do
      if bits == 0 then
        --assert(self.limit > 0)
        self.limit -= 1
        buffer = @self.address
        self.address += 1
        bits = 8
      end

      local consume = min(bits, lw)
      result = (result << consume) | (buffer >> (bits - consume))
      result &= 0xFF -- the remaining bits must not go into the fraction
      bits -= consume
      buffer &= ((1<<bits) - 1)
      lw -= consume
    end
    add(ret,result)
  end

  self.buffer = buffer
  self.read_bits = bits
  return unpack(ret)
end
function stream:write(v)
  if (v==nil) v=0
  --assert(v>=0 and v<256)
  --assert(self.limit > 0)
  self.limit -= 1

  poke(self.address, v)
  self.address+=1
  end
function stream:write2(v)
  --assert(self.limit > 1)
  self.limit -= 2

  poke2(self.address, v)
  self.address+=2
end
function stream:pack(width, ...)
  local bits=self.write_bits
  local buffer=self.buffer
  local values={...}

  for v in all(values) do
    local remaining = width
    --assert(v>=0 and v<(1<<remaining))
    while remaining > 0 do
      local consume = min(bits, remaining)
      buffer = (buffer << consume) | (v >> (remaining - consume))
      bits -= consume
      if bits == 0 then
        poke(self.address, buffer)
        --assert(self.limit > 0) self.limit -= 1
        self.address+=1
        bits = 8
        buffer = 0
      end
      remaining -= consume
      v &= ((1<<remaining) - 1)
    end
  end

  self.buffer=buffer
  self.write_bits=bits
end


-- list all the sprite values that can be saved here.
-- we store the index in this list (so it can fit in
-- 5 bits!) rather than the raw sprite index itself.
save_item_code=split"0,160,144,145,146,147,250"

function save_game()
  -- note: we work very hard to get in our 256 bytes here
  --       so that save-games work in the web player. we
  --       could theoretically use cstore() to let us save
  --       way more data, but that comes with other limits
  -- compare with load_game
  local w = stream:new(0x5e00,256)

  -- write a version byte first so that we know if there's
  -- a savegame or not. We should probably find something
  -- to pack in here but....
  w:write(0x03)               -- 1

  w:pack(4,log_count,chapter) -- 2

  -- all these have more than 4 bits of value, kinda.
  w:write(day%112)            -- 3
  -- hour = 8
  -- tank_level = 100
  -- energy_level = 100
  w:write(grabbed_item)       -- 4

  -- now pack up the seeds. we have 16 flower seeds,
  -- and each uses two bytes, so we use 32 bytes here.
  assert(#flower_seeds==16)
  for fs in all(flower_seeds) do
    w:write2(fs.seed<<16)
  end                         -- 36

  -- now pack up the items. each item gets 6 bits.
  -- the high bits are the signal bits:
  --
  --   0b00xxxx     xxxx  = raw sprite index
  --   0b01xxxx     xxxx  = tree (xxxx=style?)
  --   0b1axxxx     xxxx  = seed index, a = age
  --                        (0=half grown, 1=full grown)
  --
  -- 16*16*6/8 = 192 bytes
  all_map(
    function(x,y,item)
      local encoded=nil
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
                --assert(si>=1 and si<=16)
                encoded = 0b100000 | (si-1)
                if flower.age > 0.5 then
                  encoded |= 0b010000
                end
              end
            end
          end
        end
      elseif item==149 then
        encoded = 0b010000
        local t = find_tree(x,y)
        if t then
          if t.s==150 then
            encoded = 0b011100
          elseif t.s==206 then
            encoded = 0b011000
          else
            encoded = 0b011001
          end
        end
      else
        for ii=1,#save_item_code do
          if save_item_code[ii]==item then
            encoded = ii
          end
        end
      end
      w:pack(6, encoded)
    end
  ) -- 228
  -- assert(w.write_bits==8 and w.buffer==0)

  -- write the flower pockets
  -- 16 flowers, 63 max=6 bits, 2 values=12 bits
  -- 16*12/8=24 bytes
  for fs in all(flower_seeds) do
    local fc,sc=0,0
    for fp in all(flower_pockets) do
      if fp.seed==fs then
        fc,sc=fp.flower_count,fp.seed_count
      end
    end
    w:pack(6, fc, sc)
  end                            -- 252
  -- assert(w.write_bits==8 and w.buffer==0)

  local want_seed,want_count=0, 0
  for fi=1,#flower_seeds do
     if flower_seeds[fi]==penny_want_seed then
        want_seed,want_count=fi-1,penny_want_count
     end
  end
  w:pack(4, want_seed, want_count)-- 253

  -- 3 bytes to spare! tree seeds maybe! :)
end

function load_game()
  -- see save_game for details
  local w = stream:new(0x5e00,256)

  if w:read() ~= 0x03 then
    return false
  end

  px = base_x
  py = base_y

  log_count,chapter = w:unpack(4, 2)
  day = w:read()
  hour = 8
  grabbed_item = w:read()
  if grabbed_item == 0 then
    grabbed_item = nil
  end

  flower_seeds={}
  for fi=1,16 do
     local seed = w:read2()
     add(flower_seeds, flower:new(flower_size, fi-1, seed>>16))
  end                      -- 39

  -- unpack the items. each item gets 6 bits.
  -- the high bits are the signal bits:
  --
  --   0b0xxxxx     xxxxx = raw sprite index
  --   0b1axxxx     xxxx  = seed index, a = age
  --                        (0=half grown, 1=full grown)
  --
  -- 16*16*6/8 = 192 bytes
  flowers={} trees={}
  all_map(
    function(x,y)
      local encoded = w:unpack(6, 1)
      if encoded & 0b100000 ~= 0 then -- flower
        local age, si = 0.5, (encoded & 0b001111)+1
        if encoded & 0b010000 ~= 0 then
          age = 1.0
        end

        --assert(si>0 and si<=#flower_seeds, x.." "..y.." "..si)
        add_flower(flower_seeds[si], age, x, y)
      elseif encoded & 0b010000 ~= 0 then
        set_item(x,y,149)
        if encoded==0b011100 then
          add_tree(x,y,150)
        elseif encoded==0b011000 then
          add_tree(x,y,206)
        elseif encoded==0b011001 then
          add_tree(x,y,238)
        end
      else
        set_item(x,y,save_item_code[encoded])
      end
    end
  )

  -- unpack the flower pockets
  flower_pockets={}
  for fi=1,16 do
    local fc,sc=w:unpack(6, 2)
    if fc>0 or sc>0 then
      --assert(fi<=#flower_seeds,tostr(fi))
      get_flower(flower_seeds[fi], fc, sc)
    end
  end

  fi,penny_want_count = w:unpack(4, 2)
  if penny_want_count>0 then
    penny_want_seed=flower_seeds[fi+1]
  else
    penny_want_seed=nil
  end


  -- deal with the chapters.
  if chapter==2 then
    script:start_ch2()
  elseif chapter==3 then
     script:start_ch3()
  elseif chapter==4 then
     script:start_ch4()
  elseif chapter==5 then
     script:start_ch5()
  else
    penny_leave()
  end

  return true
end

-- function dump_hex()
--   local w = stream:new_read(0x5e00,256)
--   for i=1,256 do
--     local b=w:read()
--     print(sub(tostr(b,true),5,6).." \0")
--     if (i%10==0) print("\n\0")
--   end
--   print("\n")
-- end

-- in v1 these were random but now, no.
base_x=24
base_y=4

-- player state
function init_player()
  d=2 spd=0.125 walking=false
  idle_time=0

  max_tank=100
  tank_level=max_tank

  energy_level=100

  walk_cost=0.1
  grab_cost=1
  saw_cost=3
  water_cost=0.2
  plant_cost=0.2

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
  menu_top=1
  menu_items={}
end

-- days are 24 hrs long
-- this is how much of an hr we
-- tick every frame. (tweak for
-- fun!)
function init_time()
  hour_inc=0.0036 --*10

  recharge_rate=100*hour_inc/4
  water_rate=100*hour_inc/2
  flower_rate=1*hour_inc/24
end

function init_game()
  blank_screen=false

  item_sel=tl_grab

  init_plants()
  init_menu()
  init_time()
  init_player()
  init_weather()
  init_text()
  init_birds()
end


flower_sy=88

function _init()
  --poke(0x5f36,0x40) -- disable print scroll
  flower:init(flower_sy)

  cartdata("doty_robo_2_p8")

  load_font()
  init_fx()

  new_game()
  init_game()

  -- -- cheatz
  -- menuitem(1,"+energy",function() energy_level=100 end)
  -- menuitem(2,"-energy",function() energy_level=mid(100,0,energy_level/2) end)
  -- menuitem(1,"rain",function() raining=not raining end)
  -- menuitem(2,"snow",function() day=2*28 raining=not raining end)
  -- menuitem(4,"load", function()
  --            if load_game() then
  --              init_game()
  --            end
  -- end)

  -- title screen
  title_screen=true
  map_left=0
  penny_show(2,2,0)
  penny_start_wander()
end

function open_item_menu()
  menu_mode=true
  menu_sel=1

  menu_items=get_items()
  for mi,it in pairs(menu_items) do
    if it==item_sel then menu_sel=mi end
    it.on_select=function(item) item_sel=item end
  end
  if chapter>1 then
    add(menu_items,{
          icon=165,
          name="sleep",
          disabled=px~=base_x or py~=base_y,
          on_select=function() sleep_until_morning() end
    })
  end

  menu_top=1
  update_fn=update_menu
end

function looking_at()
  if d==0 then return px-1,py end --left
  if d==1 then return px+1,py end --right
  if d==2 then return px,py+1 end --down
  return px,py-1 --up
end

-- flags:
-- 0: collision
-- 1: cannot plant
-- 2: grab-able
-- 3: cut-able
-- 4: cannot dig
-- 5: wet
-- 6: tp outside/inside
--
function map_flag(x,y,f)
  return fget(mget(x,y),f) or
     fget(get_item(x,y),f)
end

function map_flag_all(x,y,f)
  return fget(mget(x,y),f) and
     fget(get_item(x,y),f)
end

function use_thing()
  local tx,ty=looking_at()
  local give=item_sel.give
  if tx==penny_x and ty==penny_y and give then
    if type(give)=="function" then
      give(item_sel)
    else
      do_script(give)
    end
  elseif item_sel.fn != nil then
    item_sel.fn(item_sel, tx, ty)
  end
end

-- anim is a comma-separated list of numbers forming frame,duration pairs
-- eg 1,34,87,12 means "frame 1 for 34 frames, then 87 for 12 frames."
function animate(anim,done)
  animation=split(anim)
  anim_done=done
  anim_index=1
  anim_duration=animation[2]
end

function update_animation()
   if animation then
      anim_duration-=1
      if anim_duration==0 then
         anim_index+=2
         if anim_index>#animation then
            animation=nil
            if anim_done then anim_done() end
         else
            anim_duration=animation[anim_index+1]
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
buzz_msg=nil
buzz_msg_time=0

function buzz(msg)
  buzz_time=3
  buzz_msg=msg
  buzz_msg_time=9
  sfx(0,3) -- buzz
end

is_sleeping = false

function sleep_until_morning()
   sleep_thread=cocreate(function()
       animate("1,15,13,15,45,15")
       yield()

       is_sleeping=true
       fade_out()

       tick_midnight()
       hour=8
       save_game()

       fade_in()
       animate("45,15,13,15,1,15")
       yield()

       energy_level=100
       is_sleeping=false
       update_fn=update_walk
   end)
   update_fn=update_sleep
   assert(coresume(sleep_thread))
end

function update_sleep()
   assert(coresume(sleep_thread))
end

function yield_until(until_hour)
  while until_hour >= 24 do
    until_hour-=24
  end
  while until_hour < hour do
    yield()
  end
  while hour < until_hour do
    yield()
  end
end

function yield_frames(f)
  for i=1,f do
    yield()
  end
end

function time_near(t)
   return abs(hour-t) <= hour_inc * 2
end

function tick_midnight()
  day+=1
  if day>=112 then
    day-=112
  end

  -- dry everything out and look for trees
  -- that might mature into full-grown trees.
  if not winter then
    for t in all(trees) do
      if t.s==150 and rnd_int(14)==true then
        -- sapling -> adult
        t.s=rnd{206,238}
      end
    end

    all_map(function(x,y,item)
        if mget(x,y)==64 then
          mset(x,y,65)
        end

        if item==250 then -- tree sprout
          if rnd_int(1)==0 then -- :testtest: 14 random chance for growth
            -- sprout -> sapling
            add_tree(x,y,150)
          end
        end
    end)
  end
end

function update_time()
  buzz_time = max(buzz_time - 0.75, 0)
  buzz_msg_time = max(buzz_msg_time - 0.75, 0)

  hour += hour_inc
  if hour>=24 then
    hour-=24
    tick_midnight()
  end

  season = flr(day/28)+1
  winter = season==3
end

function update_bgm()
  if not stat(57) then
     if time_near(10) then
        music(2)
     elseif time_near(14) then
        music(0)
     elseif time_near(20) then
        music(3)
     end
  end
end

function update_core()
  -- this is the core update fn
  -- of the game: what runs while
  -- you're "playing" the game.
  --
  -- most of the subsystems only
  -- update while you're playing,
  -- and are paused any other
  -- time (cutscenes, etc.)
  update_time()
  update_weather()
  update_plants()
  penny_update()
  update_birds()
  update_bgm()
end

function update_walk()
  update_core()
  check_objective()

  if px==tx and py==ty then
    if btnp(⬅️) then
      if d~=0 then d=0 else tx=px-1 end
    elseif btnp(➡️) then
      if d~=1 then d=1 else tx=px+1 end
    elseif btnp(⬇️) then
      if d~=2 then d=2 else ty=py+1 end
    elseif btnp(⬆️) then
      if d~=3 then d=3 else ty=py-1 end
    end
    if tx-map_left<0  then buzz() tx=map_left+0  end
    if tx-map_left>15 then buzz() tx=map_left+15 end
    if ty<0  then buzz() ty=0  end
    if ty>15 then buzz() ty=15 end
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
  else -- if not walking then
    if btnp(❎) and
      grabbed_item==nil then
      open_item_menu()
    end
    if btnp(🅾️) then
      use_thing()
      idle_time=0
    end
  end

  if map_flag(px,py,6) then
     -- todo: transitions?
     if map_left>0 then
        py=1 px-=15
     else
        py=7 px+=15
     end
     tx,ty=px,py
  end

  if energy_level<=0 then
     -- uh oh, trouble.
     if chapter < 2 then
        do_script(cs_firstcharge)
     else
        do_script(cs_nobattery)
     end
  end

  idle_time+=0.0333
end

function update_menu()
  if btnp(⬇️) then menu_sel+=1 end
  if btnp(⬆️) then menu_sel-=1 end
  menu_sel=mid(1,menu_sel,#menu_items)

  if btnp(❎) then
    menu_mode=false
    update_fn=update_walk
  end
  if btnp(🅾️) then
    local it=menu_items[menu_sel]
    if it.disabled then
      sfx(0,3) -- buzz
    else
      menu_mode=false
      update_fn=update_walk
      it.on_select(it)
    end
  end

  -- scroll?
  if menu_sel<menu_top then
     menu_top=menu_sel
  elseif menu_sel>menu_top+7 then
     menu_top=menu_sel-7
  end
end

function update_title()
  update_core()
  if btnp(⬇️) and @0x5e00>0 then
     menu_sel=2
  elseif btnp(⬆️) then
     menu_sel=1
  elseif btnp(🅾️) then
     reload()
     title_screen=false
     if menu_sel==1 then
        new_game()
        init_game()
        do_script(cs_intro)
     else
        load_game()
        init_game()
        update_fn=update_walk
     end
  end
end

update_fn=update_title

function _update()
  update_animation()
  update_particles()
  if animation==nil then
    update_fn()
  end
end

function draw_box(x, y, w, h)
  palt(0, false)
  palt(12, true)
  spr(128,x,y)

  local xr = x+(w+1)*8
  local yb = y+(h+1)*8

  for ix=1,w do
    spr(129,x+ix*8,y)
    spr(129,x+ix*8,yb,1,1,false,true)
  end

  spr(128,xr,y,1,1,true)
  for iy=1,h do
    spr(130,x, y+iy*8) -- ,1,1,false
    spr(130,xr,y+iy*8,1,1,true)
  end
  spr(128,x,yb,1,1,false,true)
  spr(128,xr,yb,1,1,true,true)

  rectfill(x+8,y+8,xr,yb,0)
  palt()
end

function draw_menu(items, selection)
  local hght=mid(ceil((2+#items)*10/8),4,10)

  draw_box(56,0,7,hght)
  clip(62,8,120,hght*8)
  local yofs=10*(menu_top-1)

  color(7)
  local lx=63
  local ly=9-yofs
  for i=1,#items do
    local it=items[i]
    if selection == i then
      print(">",lx,ly)
    end
    if it.icon then
      spr(it.icon,lx+6,ly-1)
    else
      sspr(
        it.sx,it.sy,
        flower_size,flower_size,
        -- x+6,y-1 looks good for 8x8 sprites,
        -- for smaller flowers we need to adjust
        -- lx+6+4-...,ly-1+4-...
        lx+10-flower_size/2,ly+3-flower_size/2)
    end
    if it.disabled then color(5) else color(7) end

    local name=it.name
    if it.name_fn then name=it:name_fn() end
    print(name,lx+16,ly)

    ly += 10
  end
end

--moon_phases={134,135,136,137,138,139,138,137,136,135}
season_names=split"summer,fall,winter,spring"

function draw_time()
  -- daytime is 06:00-18:00
  -- night is 18:00-06:00
  -- NOTE: This different from the "daytime" which penny uses.
  -- where are we?
  local bg=12
  local fg=9
  local sp=133
  local fl=false

  local frc
  local is_night=true
  if hour>=6 and hour<18 then
     frc=(hour-6)/12
     is_night=false
  elseif hour>=18 then
     frc=(hour-18)/12
  else
     frc=(hour+6)/12
  end

  if is_night then
     -- 3 days in a phase
     -- 10 moon phases in a month
     -- :note: this doesn't align with calendar "season"
     -- months (which would be 2.8 days/phase) and i
     -- kind of love it.
     local phase=flr(day/3)%10

     --sp,fl=moon_phases[phase+1],phase>5
     sp,fl=134+phase,phase>5
     if fl then sp=139-(phase-5) end

     bg=0 fg=5
  end

  rectfill(16,2,110,11,bg)
  rect(16,2,110,11,fg)
  spr(sp,16+(87*frc),3,1,1,fl)

  local sn,dos=season_names[season],tostr(day%28+1)
  local ld=sub(dos,#dos)
  if ld=="1" and dos~="11" then
     dos..="st"
  elseif ld=="2" and dos~="12" then
     dos..="nd"
  elseif ld=="3" and dos~="13" then
     dos..="rd"
  else
     dos..="th"
  end
  dos..=" of "..sn
  printo(dos,64-2*#dos,13,7)
end

function draw_item()
  draw_box(96,104,2,1)
  print("🅾️",103,114,7)
  if item_sel.icon then
    spr(item_sel.icon,112,112)
  else
    sspr(
      item_sel.sx,item_sel.sy,
      flower_size,flower_size,
      116-flower_size/2,116-flower_size/2)
  end
end

function draw_meters()
  draw_box(104,50,1,5)
  if chapter>=4 then
    local tank_frac=(max_tank-tank_level)/max_tank
    rectfill(111,57+41*tank_frac,115,98,12)
  end

  local nrg_ofs=0
  if chapter<4 then nrg_ofs=5 end
  local nrg_frac=(100-energy_level)/100
  local nrg_color
  if nrg_frac<0.5 then
    nrg_color=11
  elseif nrg_frac<0.7 then
    nrg_color=10
  else
    nrg_color=8
  end
  rectfill(116-nrg_ofs,57+41*nrg_frac,120,98,nrg_color)
end

function draw_map()
   local ofx, ofy=sin(buzz_time),0
   if buzz_time>0 then
      ofy+=cos(buzz_time)
   end
   if winter then
      pal(5,6) pal(1,7)
   end
   map(map_left, 0,ofx,ofy,16,16) -- base
   pal()
   map(map_left,16,ofx,ofy,16,16) -- item
end

function draw_player()
  local idx=1
  local fl=false

  if animation then
     idx=animation[anim_index]
  elseif grabbed_item then
     idx=35
  elseif is_sleeping then
     idx=45
     d=2
  elseif not title_screen then
     if (flr(time()*4)%2)==0 then
        idx+=2
     end
  end

  --if d==2 then fl=false end
  if     d==3 then idx+=8
  elseif d==1 then idx+=4
  elseif d==0 then idx+=4 fl=true
  end

  local sc_x, sc_y = (px-map_left)*8-4,py*8-8

  -- draw robo.
  palt(0, false)
  palt(12, true)
  spr(idx,sc_x,sc_y,2,2,fl)
  palt()
end

function draw_grabbed_item()
  local sw,dx=1
  if grabbed_item==150 then
    dx=({-14,0,-8,-8})[d+1] sw=2
  else
    dx=({-14,6,-4,-4})[d+1]
  end

  local sc_x,sc_y=(px-map_left)*8+4+dx,py*8-10
  spr(grabbed_item,sc_x,sc_y,sw,sw)
end

function draw_base()
   local bsx=8*(base_x-map_left)
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

function printo(t,x,y,c)
  color(0)
  print(t,x-1,y)
  print(t,x+1,y)
  print(t,x,y-1)
  print(t,x,y+1)
  print(t,x,y,c)
end

descs={
  [160]="rock",
  [144]="grass",
  [145]="grass",
  [146]="grass",
  [147]="grass",
  [250]="tree sprout",
}

function draw_objective()
  local lines={}

  local tx,ty=looking_at()
  local f=find_flower(tx,ty)
  if f then
     add(lines, f.seed.name)
     if f.age>=1.0 then
        add(lines,"full grown")
     elseif not map_flag(f.x, f.y, 5) then
        add(lines,"needs water")
     else
        add(lines,"growing")
     end
  else
    local t=find_tree(tx,ty)
    if t then
      add(lines,"tree")
      if t.s==150 then
        add(lines,"sapling")
      end
    else
      add(lines,descs[get_item(tx,ty)])
    end
  end

  local obj=objective
  if not obj and penny_want_seed then
     -- do wee have enough?
     if has_wanted_flowers() then
        obj="give "..penny_want_seed.name.." to penny"
     else
        obj="get "..penny_want_count.." "..penny_want_seed.name.." flowers"
     end
  end
  if obj then
    add(lines, "goal: "..obj)
  end

  local ly=129-8*#lines
  for l in all(lines) do
     printo(l, 2, ly, 7)
     ly+=8
  end
end

-- function draw_debug()
--   cursor(0,0,7)
--   if px!=nil and py!=nil then
--     print("x "..px.." y "..py.." t "..hour)
--     local tx,ty=looking_at()
--     print("tx "..tx.." ty "..ty)
--   end
--   if chapter != nil then
--     print("chapter: "..chapter)
--   end
--   if penny_x!=nil then
--     print("penny x "..penny_x.." y "..penny_y.." s "..penny_speed)
--     print("      f "..penny_frame.." d "..penny_d)
--     if penny__thread and costatus(penny__thread) ~= "dead" then
--       if penny_DBG_thread_name then
--         print("      act: "..penny_DBG_thread_name)
--       else
--         print("      act: ????")
--       end
--     end
--     local gx,gy=penny_x*8,penny_y*8
--     rect(gx,gy,gx+8,gy+8,4)
--   end
--   -- for fi=1,#flowers do
--   --    local f=flowers[fi]
--   --    print(fi.." "..f.seed.name.." "..f.x.." "..f.y)
--   -- end
--   -- if DBG_last_ys then
--   --    for yi=1,#DBG_last_ys do
--   --       local ly=DBG_last_ys[yi]
--   --       local la=DBG_last_draws[yi][2]
--   --       if type(la)=="table" then
--   --          la=la.seed.name
--   --       end
--   --       print(ly.." "..la)
--   --    end
--   -- end

--   -- check the dumb clearing
--   -- rect(px*8,py*8,(px+6)*8,(py+6)*8,10)
--   -- if not _check_clear(px,py) then
--   --    rect(
--   --       DBG_clear_fail_pt[1]*8,
--   --       DBG_clear_fail_pt[2]*8,
--   --       DBG_clear_fail_pt[1]*8+8,
--   --       DBG_clear_fail_pt[2]*8+8,
--   --       7)
--   -- end
-- end

-- the main rendering function
-- since almost everything is
-- always on the screen at the
-- same time.
function draw_game()
  -- map left always follows the player...
  -- :todo: use camera() for this
  if not title_screen then
    map_left = flr(px/16)*16
  end

  -- make sure we draw the world
  -- objects in the right order.
  local draws={
    {draw_player,"robo"},
    {draw_base,"base"},
    {draw_penny,"pny"},
  }
  local ys={py, base_y, penny_y+0.1}
  if grabbed_item then
    add(draws, {draw_grabbed_item})
    if d==3 then add(ys, py-0.1) else add(ys, py) end
  end
  if map_left==0 then
    for t in all(trees) do
      add(draws, {draw_tree, t})
      add(ys, t.y)
    end
    for f in all(flowers) do
      add(draws, {draw_flower,f})
      add(ys, f.y-0.1)
    end
    for b in all(birds) do
      add(draws, {draw_bird,b})
      add(ys, b.ty)
    end
  end
  sort(ys,draws)

  -- ===========================
  -- draw clip window
  -- ===========================
  -- This is the code that renders
  -- the world behind the trees.
  --
  local _px,_py=px*8-12,py*8-16
  clip(_px,_py,32,32)

  enable_leaves=false
  draw_map()
  for dd in all(draws) do
    dd[1](dd[2])
  end

  for ppx=_px,_px+32 do
    local cval=(ppx-_px-16)/16
    cval=1-sqrt(1-cval*cval)

    cval=cval*16+0.01

    line(ppx,_py,ppx,_py+cval,12)
    line(ppx,_py+32-cval,ppx,_py+32,12)
  end
  fillp(0b1010010110100101.1)
  circfill(_px+16,_py+16,16,12)
  fillp()
  clip()

  -- Back up screen (at 0x6000) to user memory (at 0x8000)
  memcpy(0x8000,0x6000,0x2000)

  -- ===========================
  -- world draw
  -- ===========================
  -- draw **everything**

  enable_lighting()

  enable_leaves=true
  draw_map()
  for dd in all(draws) do
    dd[1](dd[2])
  end

  -- ===========================
  -- blit clip window
  -- ===========================
  -- draw what's behind the trees
  memcpy(0xA000,0x0000,0x2000) -- back up sprites to user memory (:todo: once on init?)
  memcpy(0x0000,0x8000,0x2000) -- copy saved background to sprites
  palt(12,true) palt(0,false)
  sspr(_px,_py,32,32,_px,_py)
  palt()
  memcpy(0x0000,0xA000,0x2000) -- restore sprites (reload bad!)

  -- now rain and stuff
  draw_weather()

  -- now draw the ui; it is not
  -- affected by lighting
  disable_lighting()

  if buzz_msg_time>0 and buzz_msg then
    printo(buzz_msg, 2, 104, 8)
  end

  -- hud and debug stuff
  if menu_mode then
    draw_menu(menu_items,menu_sel)
  elseif idle_time>1 then
    draw_item()
    draw_time()
    draw_meters()
    draw_objective()
  elseif (energy_level/100)<0.25 then
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
  cls(0)
  if not blank_screen then
    draw_game()
  end

  -- the little box where people
  -- talk. (in 'cutscene stuff')
  draw_text()

  -- tw,th=draw_string(...
  if title_screen then
    spr(152, 32, 56, 8, 2)

    printo("new game",48,100,7)
    if (@0x5e00>0) printo("continue",48,108,7)

    local sy=100
    if menu_sel==2 then sy=108 end
    printo(">",42,sy,7)

    print("v2.00A",104,122)
  end
end

-->8
-- water and birds
-- :todo: water levels?
function wet_ground(tx, ty)
  if mget(tx,ty)==64 then
    mset(tx,ty,65)
  end
end

function i_water(item,tx,ty)
  if tank_level < 10 then
    buzz("water tank empty")
    return
  end

  if energy_level<water_cost then
    buzz("insufficient power")
    return
  end

  energy_level-=water_cost
  animate(
     "35,10",
     function()
        tank_level-=10
        wet_ground(tx, ty)
     end
  )
end

function init_birds()
  birds={}
end

function add_bird()
  local tx,ty=rnd_int(10)+3,rnd_int(10)+3
  local b
  b={
    x=tx-16, y=ty-16, ty=ty, frame=1, c=rnd{8,13,14},
    thread=cocreate(function()
        -- bird is arriving.
        while b.x<tx do
          b.x+=0.2 b.y+=0.2
          b.frame+=0.5
          if (b.frame>=4) b.frame=1
          yield()
        end

        -- bird is singing and dropping seed.
        b.frame=0
        for i=1,rnd_int(4)+1 do
          -- is the chirping good?
          -- if (not is_sleeping) sfx_yield(2, 3)
          yield_frames(15)
        end
        if (title_screen or chapter>=0) and not map_flag(tx,ty,1) then
          if rnd_int(1)==0 then -- :testtest: should be 17, ch4
            set_item(tx,ty,250) -- tree sprout
          else
            add_flower(rnd(flower_seeds), 0.25, tx, ty)
          end
        end

        -- bird is leaving.
        tx+=16 ty-=16
        while b.x<tx do
          b.x+=0.2 b.y-=0.2
          b.frame+=0.5
          if (b.frame>=4) b.frame=1
          yield()
        end

        del(birds,b)
    end)
  }
  add(birds, b)
end

function update_birds()
  if not raining and #birds<1 and hour>4 and hour<16 then
    add_bird()
  end

  for b in all(birds) do
    assert(coresume(b.thread))
  end

  if #birds>0 and rnd_int(150)==0 and not raining then
    sfx(2,3) -- chirp!
  end
end

function draw_bird(bird)
  for b in all(birds) do
    pal(4,b.c)
    spr(flr(161+b.frame),(b.x-map_left)*8,b.y*8)
    pal()
  end
end

-->8
-- actual flower stuff.

flower={}
function flower:init(sy)
   flower.sy=sy
end

function rnd_int(n)
   return flr(rnd(n))
end

function flip_coin()
   return rnd_int(2)==0
end

function rnd_chr(s)
   local i=rnd_int(#s)+1
   return sub(s,i,i)
end

function flower:name()
   local cons="wrtpsdfghjklzxcvbnm"
   local vowl="aeiou"

   local result=rnd_chr(cons)..rnd_chr(vowl)
   if flip_coin() then
      result=result..rnd_chr(cons)..rnd_chr(vowl)
   else
      result=result..rnd({"th","ch","ph","ke","te","se"})
   end

   return result
end

function flower:new(size, slot, seed, stem)
   seed=seed or rnd()
   if stem==nil then stem=true end
   srand(seed)

   local flx=flip_coin()

   local f={
      size=size,
      seed=seed,
      stem=stem,
      symm=rnd_int(2),
      flx=flx,
      slot=slot,
      name=self:name()
   }

   local colors={}
   while colors[4]==colors[5] do
      colors={
         0,0,0,
         rnd_int(8)+8,
         rnd_int(8)+8
      }
   end

   -- Flowers are rendered into the sprite sheet starting
   -- at y 64 and left-to-right at slot*size. So if size
   -- is 6, which is typical, then the first one is at (0,64)
   -- and the next one is at (6,64), etc.
   for y=0,size-1 do
      for x=0,size-1 do
         local c=rnd(colors)
         sset(x+slot*size,y+self.sy,c)
         if f.symm==0 then
            sset(y+slot*size,x+self.sy,c)
         else
            sset(size-1-x+slot*size,y+self.sy,c)
         end
      end
   end

   return setmetatable(f,{__index=self})
end

function flower:draw(x,y,scale)
 local sz=self.size
 local flx=self.flx

 if self.stem then
  palt(0, false)
  palt(12, true)

  local sx=flr(x-16*scale/2)
  local sy=flr(y-16*scale)

  -- stem sprite starts at sprite 100
  -- because that's an empty space in
  -- all the sprite sheets i care about.
  -- :)
  sspr(
   32+16*self.symm,48,16,16,
   sx,sy,16*scale,16*scale,
   flx)

  palt()
 end

 local fx=flr(x-sz*scale/2)
 local fy=flr(y-(16+sz)*scale/2)

 function go(dx,dy)
    sspr(
       self.slot*sz,flower.sy,sz,sz,
       fx+dx,fy+dy,sz*scale,sz*scale,
       flx)
 end

 for c=1,16 do pal(c,0) end
 for dy=-1,1 do
    for dx=-1,1 do
       go(dx,dy)
    end
 end
 pal()

 go(0,0)
end
-->8
-- plants and items

flower_seeds={}
flowers={}
flower_size=6

function init_plants()
  -- these are all the live
  -- plants, really just grass
  -- these days, but also baby
  -- trees.
  plants={}
  all_map(function(x,y,sp)
      if sp>=144 and sp<147 then
        add(plants,{age=rnd(),x=x,y=y})
      end
  end)
end

function update_plants()
  for p in all(plants) do
     local sp = get_item(p.x, p.y)
     if sp<147 then
        local age=p.age + 0.0006 --grass_rate
        if age>=1 then
           age-=1
           set_item(p.x, p.y, sp+1)
        end
        p.age=age
     end
  end

  for f in all(flowers) do
    if map_flag(f.x, f.y, 5) then
      f.age=min(f.age+flower_rate, 1)
    end
  end

  for t in all(trees) do
    if t.angle then
      t.angle+=0.025
      if t.angle>=0.25 then
        sfx(5,3) -- crash!
        del(trees,t)
      end
    end
  end
end

function draw_tree(t)
  local tpx,tpy=t.x*8, t.y*8
  spr_r(t.s, tpx-4, tpy-8, t.angle, 2, 2, 8, 16)
  if enable_leaves and t.s~=150 then
    spr_r(202, tpx-12, tpy-24, t.angle, 4, 3, 16, 32)
  end
end

function find_tree(x,y)
  for t in all(trees) do
    if t.x==x and t.y==y then
      return t
    end
  end
end

function add_tree(x,y,s)
  set_item(x,y,149)
  add(trees,{x=x,y=y,s=rnd{206,238}})
end

function draw_flower(plant)
   -- ok we have an x and a y which are tile coords
   -- and a seed which is a flower{} object
   -- flower:draw() takes the bottom center location
   plant.seed:draw(4+(plant.x-map_left)*8, 8+plant.y*8, plant.age)
end

function find_flower(x,y)
  for f in all(flowers) do
    if f.x==x and f.y==y then
      return f
    end
  end
end

function remove_plant(x,y)
  for p in all(plants) do
    if p.x==x and p.y==y then
      del(plants, p)
      return
    end
  end

  local f = find_flower(x,y)
  if f then
    del(flowers, f)
  end
end

function add_flower(seed, age, tx, ty)
  add(flowers, {x=tx,y=ty,seed=seed,age=age})
  set_item(tx,ty,148) -- add placeholder
end

function script:give_flower_post()
   if chapter==4 then
      chapter=5
   end
   penny_start_leave_then_wander()
end

function give_flower(item)
  if item.flower_count > 0 then
    if item.seed==penny_want_seed then
      if item.flower_count >= penny_want_count then
        do_script([[
p=py_up_talk
Oh, a bunch of ^$1|flowers!

p=py_mid_talk
I'll take them to|mom.
I'm sure she'll love|them!

call=give_flower_post
]], {item.name})
        item.flower_count-=penny_want_count
        penny_want_count=0
        penny_want_seed=nil
      else
        local more = penny_want_count-item.flower_count
        do_script([[
p=py_up_talk
That's the|flower I want!

p=py_mid_talk
Can you collect $1|more?
        ]],{more})
      end
    elseif penny_want_seed then
       do_script([[
p=py_mid_talk
That's a very pretty|^$1 flower.

p=py_mid_wry
I am looking for a|$2, though.

p=py_mid_talk
Can you grow me|some?
      ]], {item.name, penny_want_seed.name})
    else
      do_script([[
p=py_mid_talk
What a pretty ^$1!
      ]], {item.name})
    end
  else
    do_script([[
p=py_mid_talk
That looks like a|^$1 seed.
Till the ground, then|plant it.
So long as the|ground stays wet,
it will grow.
        ]], {item.name})
  end
end

function get_flower(seed, flower_count, seed_count)
  local fp=nil
  for fi in all(flower_pockets) do
    if fi.seed==seed then
      fp=fi break
    end
  end

  if not fp then
    fp = {sx=seed.slot*flower_size,sy=flower_sy,
          name=seed.name,fn=i_plant,give=give_flower,
          seed=seed,flower_count=0,
          seed_count=0}
    function fp:name_fn()
      return self.name.."  "..self.flower_count.."/"..self.seed_count
    end
    add(flower_pockets,fp)
  end

  fp.seed_count=min(63,fp.seed_count+seed_count)
  fp.flower_count=min(63,fp.flower_count+flower_count)
end

function i_plant(item,tx,ty)
  if map_flag(tx,ty,1) then
    buzz("can't plant here")
  elseif energy_level < plant_cost then
    buzz("insufficient energy")
    return
  elseif item==tl_grass then
    add(plants, {age=0,x=tx,y=ty})
    set_item(tx,ty,144)

    energy_level-=plant_cost
  elseif item.seed_count==0 then
    buzz("no more seeds")
  else
    item.seed_count-=1
    add_flower(item.seed, 0.25, tx, ty)
    energy_level-=plant_cost
  end
end


function i_grab(item,tx,ty)
  local tgt=get_item(tx,ty)
  if grabbed_item then
    -- drop
    if fget(tgt,0) or
      tx < 0 or ty < 0 or
      tx > 15 or ty > 15 then
      if grabbed_item==150 and tgt==132 then
        add_tree(tx,ty,150)
        grabbed_item=nil
      else
        -- nopers
        buzz("can't drop here")
      end
    elseif grabbed_item==150 then
      buzz("no hole")
    else
      set_item(tx,ty,grabbed_item)
      remove_plant(tx,ty)
      grabbed_item=nil
    end
  elseif fget(tgt,2) then
    if energy_level>grab_cost then
      local flower = find_flower(tx, ty)
      if flower then
        if flower.age>=1 then
          get_flower(flower.seed, 1, 3)
        else
          get_flower(flower.seed, 0, 1)
        end
        remove_plant(tx,ty)
      elseif tgt==149 then
        local tree=find_tree(tx, ty)
        if tree.s==150 then
          grabbed_item=150
          del(trees, tree)
          set_item(tx,ty,132) -- hole
        else
          buzz("too big")
          return
        end
      else
        grabbed_item=tgt
        set_item(tx,ty,0)
      end
      energy_level-=grab_cost
    else
      buzz("insufficient energy")
    end
  end
end

function give_tool(item)
  if chapter==3 then
    if objective == "talk to penny" then
      objective=nil
      do_script(cs_didclear)
    else
      do_script([[
p=py_mid_talk
Help me move these|rocks, ok?
We need a big clear|space.
      ]])
    end
  elseif grabbed_item then
    do_script([[
p=py_down_wry
Hey, careful where|you put that.
    ]])
  elseif has_wanted_flowers() then
     do_script([[
p=py_mid_wry
Hey there Robo!
Did you have|flowers for me?
Pick them from the|menu and show me.
     ]])
  else
    do_script([[
p=py_mid_talk
Hey there Robo!
Enjoying yourself?
    ]])
  end
end

function i_saw(item,tx,ty)
  if energy_level<saw_cost then
    buzz("insufficient energy")
    return
  end

  energy_level-=saw_cost
  sfx(4,3) -- saw
  animate(
     "33,16",
     function()
       local t=find_tree(tx,ty)
       if t then t.angle=0 end
       log_count=min(log_count+1,8)
     end
  )
end

function i_shovel(item,tx,ty)
  if energy_level<saw_cost then
    buzz("insufficient energy")
  elseif map_flag(tx,ty,4) then
    buzz("cannot dig")
  else
    local target,sound_effect,animation=
      get_item(tx,ty),6,"33,10,35,8,33,10,35,8"
    if target==149 and find_tree(tx,ty) then
      buzz("tree too big")
    elseif target==132 then
      animation="3,4,33,8,3,4,33,8"
      sound_effect=7
    end

    energy_level-=saw_cost
    sfx(sound_effect,3) -- bloop!
    animate(
      animation,
      function()
        sfx(sound_effect,-2)
        -- hole in the ground
        if target==132 then
          set_item(tx,ty,0)
        else
          set_item(tx,ty,132)
        end
      end
    )
  end
end

function tool(icon,name,fn,give)
  return {icon=icon,name=name,fn=fn,give=give}
end

tl_grab=tool(142,"grab",i_grab,give_tool)
tl_saw=tool(140,"saw",i_saw,[[
p=py_mid_talk
Hey, careful with|that!
That thing's sharp!
]])
tl_shovel=tool(131,"shovel",i_shovel,[[
p=py_up_talk
That's a shovel,|ya dig?
]])
tl_water=tool(143,"water",i_water,[[
p=py_up_talk
Don't get me wet!

p=py_mid_wry
Save that for the|plants.
]])
tl_grass=tool(147,"grass",i_plant,[[
p=py_mid_talk
Grass seeds!

p=py_down_smile
I love the feel of|grass under my feet.
]])

function give_logs()
end

tl_logs=tool(120,"logs",i_logs,give_logs)
function tl_logs:name_fn()
  return "logs  "..log_count
end

function get_items()
  local items={tl_grab,tl_saw,tl_shovel}
  if chapter >= 4 then
    add(items,tl_water)
    add(items,tl_grass)
  end
  if log_count>0 then
    add(items,tl_logs)
  end
  for fp in all(flower_pockets) do
    add(items, fp)
  end

  return items
end
-->8
-- weather
--
function init_weather()
  raining=false
  rain={}
  max_rain=2000
  weather_elapsed=6
  season_rain = split"10,4,2,3" -- 1 is summer
end

function update_weather()
  weather_elapsed += hour_inc
  if weather_elapsed>=6 then
    weather_elapsed-=6
    local chance=season_rain[season]
    --assert(chance > 1, tostr(chance).." ??")
    if rnd_int(chance) == 0 then
      raining=true
      sfx(3,2)
    else
      raining=false
      sfx(3,-2)
    end
  end
end

function update_particles()
  if raining and #rain<max_rain then
    for i=1,rnd(40) do
      local ty,life=rnd_int(136),rnd_int(10)
      local drop={
         x=rnd_int(136),
         y=ty-3*life,
         life=life,
         o=rnd()
      }
      if winter then
        drop.y=ty-0.5*life
      end
      add(rain, drop)
    end
  end

  for drop in all(rain) do
    if winter then
      drop.y+=1
      drop.x+=sin(t()+drop.o)/2
      drop.life-=0.5
    else
      drop.y+=3
      drop.x+=1
      drop.life-=1
    end
    if drop.life < 0 then
      del(rain,drop)
      if drop.x<128 and drop.y<128 then
        wet_ground(flr(drop.x/8),flr(drop.y/8))
      end
    end
  end
end

function draw_weather()
  if map_left>0 then return end
  for r in all(rain) do
    if winter then
      circ(r.x,r.y,1,7)
    elseif r.life==0 then
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
  sunshine_map={}
  for i=0,4   do sunshine_map[i]=3    end
  for i=5,8   do sunshine_map[i]=8-i  end
  for i=9,16  do sunshine_map[i]=0    end
  for i=17,19 do sunshine_map[i]=i-16 end
  for i=20,24 do sunshine_map[i]=3    end
end

function enable_lighting()
  local light_level = light_override or sunshine_map[flr(hour)]
  dark_level=dark_levels[light_level]
  pal(dark_level)
  pal=fx_pal
end

function disable_lighting()
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

function fade_out()
   for fade_lvl=sunshine_map[flr(hour)],5 do
     light_override = fade_lvl
     yield_frames(5)
   end
   light_override = nil
end

function fade_in()
  for fade_lvl=5,sunshine_map[flr(hour)],-1 do
    light_override = fade_lvl
    yield_frames(5)
  end
  light_override = nil
end

-- draw a sprite, rotated.
-- soooo... much... tokens....
function spr_r(s,x,y,a,w,h,x0,y0)
  -- :todo: consider using tline http://dotyl.ink/l/fnq3r3fgem
  --        could be faster and prettier
  if a then
    local sw,sh,sx,sy,sa,ca=w*8,h*8,(s%16)*8,flr(s/16)*8,sin(a),cos(a)
    for ix=-sw,sw do
      for iy=-sh,sh do
        local dx,dy=ix-x0,iy-y0
        local xx,yy=dx*ca-dy*sa+x0,dx*sa+dy*ca+y0
        if xx>=0 and xx<sw and yy>=0 and yy<=sh then
          local pval=sget(sx+xx,sy+yy)
          if pval~=0 then
            pset(x+ix,y+iy,pval)
          end
        end
      end
    end
  else
    spr(s,x,y,w,h)
  end
end

-- function dump_darkness()
--    pal()
--    for ilvl=1,#dark_levels do
--       local lvl=dark_levels[ilvl]
--       for ic=1,#lvl do
--          local y=(ilvl-1)*4
--          local x=(ic-1)*4
--          rectfill(x,y,x+3,y+3,lvl[ic])
--       end
--    end
-- end

-- function repr(o)
--    local t = type(o)
--    if o == nil then
--       return "nil"
--    elseif t == "table" then
--       local r = "{"
--       local first_item=true
--       for i=1,#o do
--          if not first_item then
--             r=r..", "
--          end
--          r=r..repr(o[i])
--          first_item=false
--       end
--       for k,v in pairs(o) do
--          if type(k)~="number" or k<1 or k>#o then
--             if not first_item then
--                r=r..", "
--             end
--             r=r..repr(k).."="..repr(v)
--             first_item=false
--          end
--       end
--       r = r.."}"
--       return r
--    elseif t == "number" then
--       return tostr(o)
--    elseif t == "string" then
--       return "'"..o.."'"
--    elseif t == "thread" then
--       return "coro"
--    elseif t == "function" then
--       return "function"
--    else
--       return "?? ("..t..")"
--    end
-- end

-->8
-- cutscene stuff

-- portaits a

-- cutscenes.
function script:show_screen()
   blank_screen=false
end

cs_intro=[[
call=intro_pre
Penny?
PENNY!
...
Where is that girl?

p=py_mid_closed
OK...|Deep breath...

p=py_up_intense
RX-228! Activate!!!

call=show_screen
p=py_up_talk
It... it works?
It works!

p=blank
PENNY?
WHERE ARE|YOU??

call=intro_penny_turn
p=py_up_intense
COMING MOM!

call=intro_penny_turn_back
p=py_mid_wry
OK. That's enough|for today.
You sit tight.
I'll be back soon to|finish up.

call=intro_post
]]

function script:intro_pre()
   blank_screen=true
   penny_show(base_x,base_y+1,0)
end

function script:intro_penny_turn()
   penny_show(penny_x,penny_y,2)
end

function script:intro_penny_turn_back()
   penny_show(penny_x,penny_y,0)
end

function script:intro_post()
  penny_leave()
  energy_level = walk_cost * 28
  tank_level = 0
  chapter = 1
end

function fadeout_charge()
  fade_out()

   px=base_x py=base_y d=2
   tx=px ty=py walking=false
   tick_midnight()

   hour=8
   blank_screen=true
end

function script:firstcharge_pre()
   fadeout_charge()

   penny_show(base_x,base_y+1,0)
   energy_level=100

   -- ♪: set the chapter early
   --     so the base glows.
   chapter = 2
end

cs_firstcharge=[[
call=firstcharge_pre
...
Hey... how'd you get|over there?
Oof...
There you go!

call=show_screen
p=py_mid_wry
Huh...
I guess you really|DO work!

p=py_up_intense
Ha! I knew it!
I AM THE BEST!

p=py_mid_talk
Well, I've fixed your|charging stand.
If you sleep there,|you'll recharge.

p=py_mid_wry
Try not to run out|of power, ok?

p=blank
PENNY!
THAT FIELD CLEAR|YET?

p=py_mid_wry
Oh, uh...
I could use some|help.
Will you come|outside with me?

call=firstcharge_ch2_transition
call=start_ch2
]]

function script:firstcharge_ch2_transition()
  penny_leave()
end

function script:start_ch2()
  penny_show(7,1,0)
  penny_start_wander()
  objective="go outside"
  objective_fn=check_outside
end

function check_outside()
  if px<16 and not penny_hidden then
    penny_face(px, py)
    do_script(cs_move_rocks)
  end
end

cs_move_rocks=[[
p=py_up_talk
Hey, there you are!

p=py_mid_talk
Mom wants a big|clear space...

p=py_down_wry
...but these rocks|are so heavy.

p=py_up_talk
Now I've got you,|though!
This will be easy|for you!
Help me move these,|OK?

call=start_ch3
]]

function script:start_ch3()
  chapter=3
  penny_start_wander()
  objective="clear a 6x6 field"
  objective_fn=check_bigspace
end

function _check_clear(x,y)
  for iy=0,5 do
    for ix=0,5 do
      if map_flag(x+ix,y+iy,0) then
        --DBG_clear_fail_pt={x+ix,y+iy}
        return false
      end
    end
  end

  --DBG_clear_fail_pt=nil
  return true
end


function check_bigspace()
  for y=1,9 do
    for x=1,9 do
      if _check_clear(x,y) then
        objective="talk to penny"
        objective_fn=nil
        return
      end
    end
  end
end

function script:start_ch4()
  chapter = 4
  tank_level = max_tank
  objective_fn=check_wanted_flowers
  penny_start_wander()
end

function check_wanted_flowers()
   if has_wanted_flowers() then
      objective_fn=nil
      penny_face(px, py)
      do_script([[
p=py_up_talk
Did you get the|flowers?
Great!|Bring them here.
      ]])
   end
end

function has_wanted_flowers()
   for fp in all(flower_pockets) do
      if fp.seed == penny_want_seed and
         fp.flower_count >= penny_want_count then
         return true
      end
   end
   return false
end

cs_didclear=[[
call=didclear_look_at
p=py_up_talk
Hey!|You did it!
Looks great!

p=py_mid_talk
Wait a bit, I'll be|back!

call=didclear_leave_come_back

p=py_mid_wry
Now, don't move, OK?
Just gonna open you|up...

call=didclear_give_tools

p=py_mid_talk
Done!
Ok, check it out.|Tools!
I've given you some|useful stuff.
You've got a|watering can...
...and this neat|little plow...
...and then this seed|pouch!

p=py_mid_wry
Press 🅾️ to open the|menu to see.

p=blank
PENNY!
YOU LEFT THE DOOR|OPEN AGAIN!

p=py_down_wry
Whoops...
She sounds mad.
Maybe some flowers|will cheer her up...
Can you get me 3|flowers?

call=start_ch4
]]

function script:didclear_look_at()
  penny_face(px, py)
end

function script:didclear_leave_come_back()
   penny_leave()

   yield_frames(15)

   penny_show(16, py+1, 2)
   penny_run_to(px, penny_y)
   penny_show(penny_x, penny_y, 0)
end

function script:didclear_give_tools()
   d=2 -- look down (face penny)
   for i=1,2 do
     sfx(1,3) -- tool sound
     yield_frames(20)
   end

   -- grant the new flower seed.
   -- this isn't in start_ch4 because we don't want to do this on
   -- load_game.
   get_flower(flower_seeds[1], 0, 3)
   penny_want_seed=flower_seeds[1]
   penny_want_count=3
end

function script:start_ch5()
  chapter = 5
  tank_level = max_tank
  penny_start_wander()
end


--


cs_nobattery=[[
call=nobattery_pre

p=blank
Robo?
Can you hear me?

call=show_screen

p=py_mid_wry
Oh, thank goodness.

p=py_up_closed
Robo, you need to be|more careful!
If you don't charge,|you'll get stuck!

p=py_mid_wry
Don't worry.
I'll always be there|to help.

call=nobattery_post
]]

-- local old_penny_visible

function script:nobattery_pre()
  fadeout_charge()

  penny_show(base_x, base_y+1, 0)
  energy_level = 100*0.75
end

function script:nobattery_post()
  penny_leave()
end

--

function check_objective()
  if objective_fn then
    objective_fn()
  end
end

local script_coro = nil

function update_script()
  idle_time = 0
  assert(coresume(script_coro))
end

function strip(txt)
   local s = 1
   while sub(txt,s,s) == " " do
      s+=1
   end
   local e= #txt
   while sub(txt,e,e) == " " and e > 0 do
      e-=1
   end
   return sub(txt,s,e)
end

function doctor(line, args)
  local ret=""
  local line_parts=split(line,"|")
  for line in all(line_parts) do
    local i=1
    while i<=#line do
      if sub(line,i,i) == "$" then
        i+=1 ret..=args[tonum(sub(line,i,i))]
      else
        ret..=sub(line,i,i)
      end
      i+=1
    end
    ret..="\n"
  end
  return ret
end

portraits={
   blank={top=nil, bot=nil},

   --  py_ear_up=194
   --  py_ear_mid=192
   --  py_ear_down=196
   --  py_head_wry=224
   --  py_head_talk=226
   --  py_head_closed=228
   --  py_head_intense=230
   py_mid_wry={top=192,bot=224},
   py_mid_talk={top=192,bot=226},
   py_mid_closed={top=192,bot=228},
   py_up_talk={top=194,bot=226},
   py_up_closed={top=194,bot=228},
   py_up_intense={top=194,bot=230},
   py_down_wry={top=196,bot=224},
   py_down_smile={top=196,bot=232},
}

function do_script(script_text, args)
   script_coro = cocreate(function()
         local p = portraits.blank
         for line in all(split(script_text,"\n")) do
            line=strip(line)
            if #line==0 then
               -- nothing
            elseif sub(line,1,2)=="p=" then
               p=portraits[sub(line,3)]
            elseif sub(line,1,5)=="call=" then
               script[sub(line,6)]()
            else
               line=doctor(line, args)
               show_text(line, p.top, p.bot)
            end
         end
         update_fn=update_walk
   end)
   update_fn=update_script
   assert(coresume(script_coro)) -- one step
end

local text

function init_text()
  text = nil
end

function show_text(t, top, bot)
  text = t
  text_time = 0
  text_limit = #text + 5
  text_sprite_top = top
  text_sprite_bot = bot

  while not btnp(🅾️) do
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
  draw_string(ss,28,103,7)

  color(7)
  if text_time==text_limit and
    time()%2>1 then
    print("🅾️",112,114)
  end

  -- portrait
  if text_sprite_top then
    spr(text_sprite_top,8,90,2,2)
    spr(text_sprite_bot,8,106,2,2)
  end
end

-- =============================
-- p e n n y
-- =============================
-- she used to be all objectish
-- but i needed to take the tokens
-- back
penny_x=nil
penny_y=nil
penny_d=0
penny_speed=0.09
penny_frame=0
penny__thread=nil

function draw_penny()
  if penny_hidden then return end
  if penny_x ~= nil then
    local f,sy,sh,sx,sw=false,32,16
    if penny_d==0 or penny_d==2 then
      sx,sw=72,10
      if penny_d==2 then
        sy+=sh
      end
      if penny_frame>=1 then
        sx+=sw
      end
    else
      if penny_frame<1 then
        sx,sw=92,12
      else
        sx,sw=105,18
      end
      if penny_d==-1 then
        f=true
      end
    end

    palt(0, false)
    palt(12, true)
    sspr(
       sx,sy,sw,sh,
       (penny_x-map_left)*8, penny_y*8-8,
       sw,sh,
       f)
    palt()
  end
end

function penny_update()
  daytime = hour >= 8 and hour <= 18
  if penny__thread and costatus(penny__thread) ~= "dead" then
    assert(coresume(penny__thread))
  end
end

function penny_face(tx, ty)
  local dx = tx - penny_x
  local dy = ty - penny_y

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
  penny_d = direction
  penny_frame = 0
end

function penny_run_to(tx, ty)
  penny_face(tx, ty)
  local direction = penny_d

  local atime, t = 0, 0
  while penny_x != tx or penny_y != ty do
    t += penny_speed
    atime += penny_speed
    while atime >= 1 do
      atime -= 1
    end

    local ox,oy=penny_x,penny_y
    local dist = (sin(t) + 1) * 0.375
    local dx,dy=tx-penny_x,ty-penny_y
    local dlen=dist / sqrt(dx*dx+dy*dy)
    dx *= dlen dy *= dlen
    penny_x = mid(penny_x, penny_x+dx, tx)
    penny_y = mid(penny_y, penny_y+dy, ty)

    penny_frame = flr(atime * 2) * 2
    yield()
  end
  penny_frame = 0
end

function penny_leave()
  if penny_hidden then
  elseif penny_x<16 then
    penny_run_to(16, penny_y)
  else
    penny_run_to(22,8)
    penny_run_to(22,9)
  end
  penny_hidden=true
end

function penny_wander_around()
  while daytime do
    local dst = rnd_int(14)+1
    local tx, ty = penny_x, penny_y
    if rnd() >= 0.5 then
      tx=dst
    else
      ty=dst
    end
    tx = mid(0,tx,15)
    ty = mid(0,ty,15)

    penny_run_to(tx, ty)

    if chapter>=4 and not penny_want_seed then
      penny_want_seed=rnd(flower_seeds)
      penny_want_count=rnd_int(7)+3
      do_script([[
p=py_mid_talk
Robo?
I was wondering...
Could you please get|me more flowers?
Mom really liked the|last ones.
$1 ^$2 flowers?
Thanks!
      ]], {penny_want_count, penny_want_seed.name})
    end

    local t=rnd(30)+45
    while daytime and t>0 do
      if abs(penny_x-px)<=2 and abs(penny_y-py)<=2 then
        --penny is close
        penny_face(px,py)
        t-=0.1
      else
        t-=1
      end
      yield()
    end
  end
end

function penny_start_wander()
  penny_DBG_thread_name = "start_wander"
  penny__thread = cocreate(function()
      while true do
        -- Wander around the field until...
        penny_wander_around()

        -- oh no, it's late! Penny, run home!
        local old_x = penny_x
        penny_leave()

        -- sleep until the morning.
        yield_until(8)

        -- come back to the field
        penny_hidden=false
        penny_run_to(old_x, penny_y)
      end
  end)
end

function penny_start_leave_then_wander()
  penny_DBG_thread_name = "start_leave_then_wander"
  penny__thread = cocreate(function()
      penny_leave()
      yield_until(hour + 1)
      penny_start_wander()
  end)
end

function penny_start_leave()
  penny_DBG_thread_name = "start_leave"
  penny__thread = cocreate(function()
      penny_leave()
  end)
end

function penny_show(x,y,d)
   penny_hidden=false
   penny_x=x penny_y=y penny_d=d
   penny_frame = 0
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
  if (c) color(c)
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
      --assert(glyph, "char "..chr(c).." not in font")
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
444444445555555500000000000000000000000055555555444444444444444444444444cc11cc11cc1f111111f1cccccccccccccccccccccccccccccccccccc
454444445155555500000000000000000000000022222522444444444444444444444444c1ff11ff1c1f1ffff1f1ccccc11ccccccccccccccccccccccccccccc
4444454455555155000000000000000000000000222525224444444444555555555555441fff11fff11f1feef1f1cccc1fe1cccccccccc11111ccccccccccccc
444444445555555500000000000000000000000022222522ffffffffff5cccccccccc5ff1fff11fff1c17dffd71ccccc1fe1ccccccccc1eeeee1cccccccccccc
44444444555555550000000000000000000000005555555544444444445cccccccccc5441fff11fff11ff7ff7ff1cccc1ffe1cccccccc1fffffe11111ccccccc
44445444555515550000000000000000000000002252222244444444445cccccccccc5441fff11fff11fdffffdf1ccccc1ff1ccccccccc1111fffff7f1cccccc
44544444551555550000000000000000000000002252522244444444445cccccccccc544c1ff11ff1c1fdffffdf1cccccc1f11ccccc1111111111f7dfe1ccccc
444444445555555500000000000000000000000022522222ffffffffff5cccccccccc5ffc1ffffff1c1fdffffdf1ccccc1ff7f1ccc177fffff111fffff1ccccc
000000000000000000000000000000000000000055555555f333333344555555555555441ffffffff11ffffffff1ccccc1f7dfe1cc177ffffffffffff1cccccc
111000111100000000000000000000000000000022222522f3333333445cccccccccc5441ffffffff11ffffffff1cccc11fffff1ccc1fffffffffff11ccccccc
221100252110000000000000000000000000000022252522f3333333445cccccccccc5441ffffffff1c1ff77ff1cc111ffffff1ccc1ffffffffffff11ccccccc
333110333311000000000000000000000000000022222522ffffffffff5cccccccccc5ffc11ffff11cc1f7777f1c177ffffff1ccc1fff111111ffffff1cccccc
4221102d44221000000000000000000000000000555555553333f333445cccccccccc544c1ffffff1cc1f1771f1c177ffffff1cccc111cccccc111111ccccccc
5511105555110000000000000000000000000000225222223333f333445cccccccccc5441fff77fff11ff1111ff11ffffefff1cccccccccccccccccccccccccc
66d5106666dd5100000000000000000000000000225252223333f33344555555555555441ff7777ff11ff1cc1ff11fffffefff1ccccccccccccccccccccccccc
776d1077776dd55000000000000000000000000022522222ffffffffff555555555555ffc11111111c1f1cccc1f1c111111111cccccccccccccccccccccccccc
88221018888221000000000000000000cccccccccccccccccccccccccccccccc00000000cc11cc11cc1f1cccc1f1cccccccccccccccccccccccccccccccccccc
9422104c999421000000000000000000cccccccccccccccccccccccccccccccc00000000c1ff11ff1c1ff1cc1ff1cccccccccccccccccccccccccccccccccccc
a9421047aa9942100000000000000111cccc00cccccccccccccccccccccccccc000000001fef11fef11ff1111ff1cccccccccccccccccccccccccccccccccccc
bb3310bbbbb3310000000000000001a1ccc0bb0ccccccccccccccccccccccccc000000001fef11fef1c1f1771f1ccccccccccccccccccccccccccccccccccccc
ccd510ccccdd51100000000000001161cc0bbbb0cccccccccccccccccccccccc000000001fef11fef1c1f7777f1ccccccccccccccccccccccccccccccccccccc
d55110dddd5110000000000000001aa1c0bb00bb0ccccccccccccccccccccccc000000001fef11fef1c1ff77ff1ccccccccccccccccccccccccccccccccccccc
ee82101eee8822100000000000111661c03b0c0b0ccccccccccccccccccccccc00000000c1ff11ff1cc1ffffff1ccccccccccccccccccccccccccccccccccccc
f94210f7fff9421000000000001aaaa1cc0bb0c0cccccccccccccccccccccccc00000000c1ffffff1c1ffffffff1cccccccccccccccccccccccccccccccccccc
01011010001010006666666600116661c003b0cccccccccccccccccccccccccc000000001ff7ff7ff11feffffef1cccccccccccccccccccccccccccccccccccc
1717717101717110666666660001aaa10bb0bb0ccccccccccccc00c00ccccccc001445441f7dffd7f11feffffef1cccccccccccccccccccccccccccccccccccc
017117100111717166566566011166613bbbbb0cccccccccccc0bb03b0c00ccc005994551fffeefff11feffffef1cccccccccccccccccccccccccccccccccccc
17177171177771106656656601aaaaa103330b0cccccccccccc033bbb00bb0cc15599444c11ffff11cc1f7ff7f1ccccccccccccccccccccccccccccccccccccc
17177171011777716656656601166661c00003b0cccccccccccc003bb0b330cc59945994c1ffffff1c1f7dffd7f1cccccccccccccccccccccccccccccccccccc
017117101717111066566566001aaaa1ccccc03b0ccccccccccccc03bb300ccc599459941ffeffeff11f1feef1f1cccccccccccccccccccccccccccccccccccc
17177171011717106656656611166661cccccc03b0cccccccccccc03b00ccccc144554451ffeffeff11f1ffff1f1cccccccccccccccccccccccccccccccccccc
0101101000010100666666661aaaaaa1cccccc03b0cccccccccccc03b0cccccc00000000c11111111c1f111111f1cccccccccccccccccccccccccccccccccccc
cccccccccccccccccc53350000000500000000000000000000555500005555000055550000555500000000000055550066555500665555000006666000076000
cccccccccccccccccc53350000000050000000000990909005777750057777500577755005777550057755500555555056677750566777500067777607666660
cccc555555555555cc53350000000505002222000099999057777775577777555777755557775555577555555555555505667765056677656677666600000000
ccc5533333333333cc5335000000500002111120099aa9005777777557777775577775555777555557755555555555555756566557565665777655550c0c0c00
cc55333333333333cc5335000005000021111112009aa99057777775577777755777755557775555577555555555555557755665577556657776000000000000
cc53335555555555cc53350006650000211111120999990057777775577777555777755557775555577555555555555557766665544666456677666600c0c0c0
cc53350000000000cc53350067650000021111200909099005777750057777500577755005777550057755500555555005666650445464540067777600000000
cc53350000000000cc5335007650000000222200000000000055550000555500005555000055550000555500005555000055550045444444000666600c0c0c00
000000000000000000000000b0000b00000000000000000000011000001110000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000003b00b3bb0000000000000000001bb110013bb1000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000b0b00b0b3b30000000000000000001bbb3411543bb100000000000000000000000000000000000000000000000000000000000000000
0000000000000000000b0b0003b30b30000000000011110001b33144541133100001110001100110000110011100000001100011001110011100111101001000
0000000000000b0000b30b00b0b3b300000000000144451001b111455bb111000017771017711771001771177710000017710177117771177711777717117100
000000000b000b00b0b30b00b0b3b30b000330000144451000101144bbbb10000017117171171717117117117100000171171711717117171171711117717100
0b00b0000b300b300b300bb00bb3b3b000033000014445510001bb4453bb10000017117171171717117117117100000171171711717117171171711017717100
00b0b0bb03b0b3b00b30b3b00bb3b3b00000000014444451001bbbb4511100000017771171171777117117117100000171111711717771171171777117177100
056666000000000044400000000000000000000000000000001b3344510000000017117171171711717117117100000171771711717117171171711017177100
665556600000044004440440000004400000044000000077001b1154510000000017117171171711717117117100000171171777717117171171710017117100
666566660000044a0044444a0000044a4444444a0007700700010154510000000017117171171711717117117100000171171711717117171171711117117100
66556666000444400044444000004440044444407700707000000145510000000017117117711777101771017100000017711711717117177711777717117100
55665565004414000004440000044440000444000707007700000144510000000001001001100111000110001000000001100100101001011100111101001000
66656565004114000004440000044444000444007007700000000144510000000000000000000000000000000000000000000000000000000000000000000000
06556650444444000044400000444444004440007700000000000154510000000000000000000000000000000000000000000000000000000000000000000000
00555500000aa0000440000004400044044000000000000000000144510000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06600060006600060066600060600660666000660066600660666066006060666066000066600600660000666060000600606066606600066006000000000000
06060606006060606006000060606000600000606060006000600060606060600060600060006060606000600060006060606060006060600006000606000006
06060606006060606006000060606660660000660066006660660066006060660060600066006060660000660060006060606066006600666006006606600066
06060606006060606006000060600060600000606060000060600060606060600060600060006060606000600060006060666060006060006000066000660660
06600060006060060006000006606600666000606066606600666060600600666066000060000600606000600066600600666066606060660006000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06666666006666666666600066666666666000666666666666666666666666666666600066666666666000666666666666666666666666666666000000000000
0000000000000ff00ff0000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000154415151014541
000000000000fef00fef00000000fef0000000000000000000000000000000000000000000000000000000000003baaaaa000000000000000155455155014451
00000000000feeeffeeef000000feeef0000000000000000000000000000000000000000000000000000000003bbbbbaaaaaaaaaa00000000154441015544510
000ffff000feeeeffeeeef0000feeeef000ffff000fff0000000000000000000000000000000000000000003bbbb3bbbbbbbbbaaaaa000000154541001445100
00ffffff00feeeeffeeeef0000feeeef00ffffff00fffff0000000000000000000000000000000000000003bbb333bbbbbbbbbbbbbbb00000154444114451000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000000bbb3bbbbbbb3bbbbbbbbbbb0000155444554410000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000003b3baaaaab3baa3baaaaabbbb000015454445410000
ffffffef0feeeeeffeeeeef00feeeeefffffffef0fffffff00000000000000000000000000000000000003bbbbbaa3bbb3bbbbbaaaaa3bb00015445454441000
fffffeef0feeeeeffeeeeef00feeeeeffffffeef0fefffff000000000000000000000000000000000003bbbb3bb3bbb3bbbb3bbbbbbbb3000015544454541000
fffffeef0feeeef00feeeeef0feeeef0fffffeef0feeffff00000000000000000000000000000000003bbb333b3bbb33bb333bbbbbbbbb000001554445441000
ffffeeef0feeeef00feeeeef0feeeef0ffffeeef0feeffff0000000000000000000000000000000000bbb33bbbbb33bb33bbbbbbb3bbbbb00001555445441000
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff0000000000000000000000000000000003b33bbb3baaaaa333bbbbbbbbb3b3bb0001545444444100
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff000000000000000000000000000000000333b333bbbbaaaa3333b3bbbb3333300001545444544100
ff0feeef0feeef0000feeeef0feeef00ff0feeef0feeeff0000000000000000000000000000000000b333bbbb3bbbbbbbb3333bbb33333000001554444554100
f00feeef0feef000000feeef0feef000f00feeef0feef000000000000000000000000000000000000333bbb333bbbbbbbbb333333333b0000001554454454100
000feeef0feef000000feeef0feef000000feeef0feef00000000000000000000000000000000000033bbb3bbbbbbb3bbbbbbbbb33b3bb000015544444444410
000feffffffef000000feffffffef000000feffffffef000000feffffffef000000feffffffef000003b33bbbbbbbbb33b3bb33bb33330000000001445141000
000ffffffffff000000ffffffffff000000ffffffffff000000ffffffffff000000ffffffffff00000333b3b3b3333b333333333333300000000001545451000
00ffffffffffff0000ffffffffffff0000ffffffffffff0000ffffffffffff0000ffffffffffff00000333333333333333333333330000000000001454510000
00fffeffffefff0000ffffffffffff0000ffffffffffff0000ffffffffffff0000ffffffffffff00000003333333333330000000000000000000001545100000
0ffeeffffffeeff00fffeeffffeefff00ffeeffffffeeff00ffeeffffffeeff00fffeeffffeefff0000000000000000000000000000000000000001445100000
0feffffffffffef00ffeffffffffeff00ffffeffffeffff00ffffeffffeffff00ffeffffffffeff0000000000000000000000000000000000000014455100000
0fff77ffff77fff00fff77ffff77fff00ffffffffffffff00fff77ffff77fff00ffffffffffffff0000000000000000000000000000000000000014451000000
fff7ddffffdd7ffffff7ddffffdd7ffffffeffffffffeffffff7ddffffdd7ffffffeffffffffefff000000000000000000000000000000000000014451000000
fff7ddffffdd7ffffff7ddffffdd7fffffffeeffffeefffffff7ddffffdd7fffffffeeffffeeffff000000000000000000000000000000000000015451000000
fffffffffffffffffffffffeeffffffffffffffeeffffffffffffffeeffffffffffffffeefffffff000011000000000000000000000000000000015451000000
ffffffeeeeffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff0001bb100000000000000000000000000000014551000000
fffffffeefffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff001133b10000000000000000000000000000014451000000
fffffeffffffffffffffffe77effffffffffffffffffffffffffffeeeefffffffffffeffffffffff01bb41310000000000000000000000000000014451000000
ffffffeeffffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff1b3341100000000000000000000000000000014451000000
00ffffffffffff0000fffffeefffff0000ffffffffffff0000fffffeefffff0000ffffffffffff00131114100000000000000000000000000000014451000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000010145100000000000000000000000000000144455100000
__label__
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
45444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444
44444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444
44544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
44444444444444444444444445666644456666444444444444444444456666444566664444444444456666444566664444444444456666444444444444444444
45444444454444444544444466555664665556644544444445444444665556646655566445444444665556646655566445444444665556644544444445444444
4444454444444544444445446665666666656666444445444444b5b4666566666665666644444544666566666665666644444544666566664444454444444544
444444444444444444444444665566666655666644444444444b4b44665566666655666644444444665566666655666644444444665566664444444444444444
44444444444444444444444455665565556655654444444444b34b44556655655566556544444444556655655566556544444444556655654444444444444444
444454444444544444445444666565656665656544445111b4b35b44111565656665656544445444666565656665656544445444666565654444544444445444
44544444445444444b54b44446556654465566544b5416661b344bb1666166544655665444544444465566544655665444544444465566544454444444544444
444444444444444444b4b4bb445555444455554444b166666134b316666615444455554444444444445555444455554444444444445555444444444444444444
444444444444444445666644b4444b4445666644444166666144441666661444b4444b44444444444444444444444444b4444b44444444444444444444444444
4544444445444444665556643b44b3bb665556644541666661000016666614443b44b3bb4544444445444444454444443b44b3bb454444444544444445444444
444445444444b5b4666566664b4b3b34666566664444166617777771666145444b4b3b344444b5b444444544444445444b4b3b34444445444444454444444544
44444444444b4b446655666643b34b346655666644444111700000071114444443b34b34444b4b44444444444444444443b34b34444444444444444444444444
4444444444b34b4455665565b4b3eee455665565444411610000000016114444b4b3b34444b34b4444444b4444444444b4b3b344444444444444444444444444
44445444b4b35b4466656565b4b3beee6ee565654444166100e00e0016615444b4b3b34bb4b35b444b445b4444445444b4b3b34b444454444444544444445444
445444444b344bb4465566544bb3b3eeeeea66544411166100e00e00166111444bb3b3b44b344bb44b344b344b54b4444bb3b3b4445444444454444444544444
444444444b34b3b4445555444bb3b3eeeee555444416666100000000166661444bb3b3b44b34b3b443b4b3b444b4b4bb4bb3b3b4444444444444444444444444
4444444445666644444444444566664eee444444441166617700007716661144b4444b4445666644444444444444444444444444444444444444444444444444
4544444466555664454444446655566eee4444444441666177777777166614443b44b3bb66555664454444444544444445444444454444444544444445444444
444445446665666644444544666566eee44445444111666177777777166611144b4b3b3466656666444445444444454444444544444445444444454444444544
44444444665566664444444466556ee64444444441666661777777771666661443b34b3466556666444444444444444444444444444444444444444444444444
444444445566556544444b445566556544444b44411666610777777016666114b4b3b3445566556544444444444444444444444444444b444444444444444444
44445444666565654b445b44666565654b445b44441666610000000016666144b4b3b34b666565654444544444445444444454444b445b444444544444445444
44544444465566544b344b34465566544b344b3411166661eee00eee166661114bb3b3b446556654445444444b54b444445444444b344b344454444444544444
444444444455554443b4b3b44455554443b4b3b41666666100000000166666614bb3b3b4445555444444444444b4b4bb4444444443b4b3b44444444444444444
44444444444444444566664445666644456666444444444444444444444444444444444444444444456666444566664445666644456666444444444444444444
45444444454444446655566466555664665556644544444445444444454444444544444445444444665556646655566466555664665556644544444445444444
44444544444445446665666666656666666566664444454444444544444445444444b5b44444b5b4666566666665666666656666666566664444454444444544
4444444444444444665566666655666666556666444444444444444444444444444b4b44444b4b44665566666655666666556666665566664444444444444444
4444444444444b4455665565556655655566556544444444444444444444444444b34b4444b34b44556655655566556555665565556655654444444444444444
444454444b445b44666565656665656566656565444454444444544444445444b4b35b44b4b35b44666565656665656566656565666565654444544444445444
445444444b344b344655665446556654465566544454444444544444445444444b344bb44b344bb4465566544655665446556654465566544454444444544444
4444444443b4b3b44455554444555544445555444444444444444444444444444b34b3b44b34b3b4445555444455554444555544445555444444444444444444
44444444444444444444444444444444456666444566664444444444444444444444444445666644444444444566664444444444456666444566664444444444
45444444454444444544444445444444665556646655566445444444454444444544444466555664454444446655566445444444665556646655566445444444
44444544444445444444454444444544666566666665666644444544444445444444b5b46665666644444544666566664444b5b4666566666665666644444544
4444444444444444444444444444444466556666665566664444444444444444444b4b44665566664444444466556666444b4b44665566666655666644444444
444444444444444444444b4444444444556655655566556544444b444444444444b34b445566556544444b445566556544b34b44556655655566556544444444
44445444444454444b445b444444544466656565666565654b445b4444445444b4b35b44666565654b445b4466656565b4b35b44666565656665656544445444
44544444445444444b344b344b54b44446556654465566544b344b34445444444b344bb4465566544b344b34465566544b344bb4465566544655665444544444
444444444444444443b4b3b444b4b4bb445555444455554443b4b3b4444444444b34b3b44455554443b4b3b4445555444b34b3b4445555444455554444444444
44444444b4444b444566664444444444444444444444444444444444456666444566664444444444b4444b44b4444b4444444444444444444444444444444444
454444443b44b3bb66555664454444444544444445444444454444446655566466555664454444443b44b3bb3b44b3bb45444444454444444544444445444444
444445444b4b3b34666566664444454444444544444445444444b5b46665666666656666444445444b4b3b344b4b3b3444444544444445444444454444444544
4444444443b34b346655666644444444444111444114411444411b4111556666611566114411144111b3111141b31b3444444444444444444444444444444444
44444444b4b3b3445566556544444b44441777141771177144177117771655651771517711777117771177771711714444444444444444444444444444444444
44445444b4b3b34b666565654b445b44441711717117171711711711716565617117171171711717117171111771714b44445444444454444444544444445444
445444444bb3b3b4465566544b344b3444171171711717171171171171556651711717117171171711717114177171b4445444444b54b4444b54b44444544444
444444444bb3b3b44455554443b4b3b444177711711717771171171171555541711117117177711711717771171771b44444444444b4b4bb44b4b4bb44444444
44444444456666444566664445666644451711717117171171711711714444417177171171711717117171141717714444444444b4444b444444444444444444
454444446655566466555664665556646617117171171711717117117144444171171777717117171171716417117164454444443b44b3bb4544444445444444
444445446665666666656666666566666617117171171711717117117144454171171711717117171171711117117166444445444b4b3b344444454444444544
4444444466556666665566666655666666171171177117771317713171444444177117117171171777117777171171664444444443b34b344444444444444444
444444445566556555665565556655655561551541144111b4b11344144444444114414414144141116611115166156544444444b4b3b34444444b4444444444
444454446665656566656565666565656665656544445444b4b3b34b444454444b445b4444445444666565656665656544445444b4b3b34b4b445b4444445444
4454444446556654465566544655665446556654445444444bb3b3b4445444444b344b34445444444655665446556654445444444bb3b3b44b344b3444544444
4444444444555544445555444455554444555544444444444bb3b3b44444444443b4b3b4444444444455554444555544444444444bb3b3b443b4b3b444444444
44444444444444444566664444444444444444444566664445666644444444444566664445666644456666444566664444444444444444444444444444444444
45444444454444446655566445444444454444446655566466555664454444446655566466555664665556646655566445444444454444444544444445444444
4444454444444544666566664444b5b444444544666566666665666644444544666566666665666666656666666566664444b5b4444445444444454444444544
444444444444444466556666444b4b444444444466556666665566664444444466556666665566666655666666556666444b4b44444444444444444444444444
44444444444444445566556544b34b44444444445566556555665565444444445566556555665565556655655566556544b34b44444444444444444444444444
444454444444544466656565b4b35b444444544466656565666565654444544466656565666565656665656566656565b4b35b44444454444444544444445444
4454444444544444465566544b344bb444544444465566544655665444544444465566544655665446556654465566544b344bb44b54b4444454444444544444
4444444444444444445555444b34b3b444444444445555444455554444444444445555444455554444555544445555444b34b3b444b4b4bb4444444444444444
444444444444444444444444456666444444444445666644b4444b44444444444444444444444444444444444444444445666644b4444b444566664444444444
4544444445444444454444446655566445444444665556643b44b3bb4544444445444444454444444544444445444444665556643b44b3bb6655566445444444
44444544444445444444b5b46665666644444544666566664b4b3b3444444544444445444444b5b44444454444444544666566664b4b3b346665666644444544
4444444444444444444b4b4466556666444444446655666643b34b344444444444444444444b4b4444444444444444446655666643b34b346655666644444444
444444444444444444b34b445566556544444b4455665565b4b3b344444444444444444444b34b44444444444444444455665565b4b3b3445566556544444444
4444544444445444b4b35b44666565654b445b4466656565b4b3b34b4444544444445444b4b35b44444454444444544466656565b4b3b34b6665656544445444
445444444b54b4444b344bb4465566544b344b34465566544bb3b3b444544444445444444b344bb44b54b44444544444465566544bb3b3b44655665444544444
4444444444b4b4bb4b34b3b44455554443b4b3b4445555444bb3b3b444444444444444444b34b3b444b4b4bb44444444445555444bb3b3b44455554444444444
44444444444444444566664444444444b4444b444444444444444444444444444444444444444444456666444444444444444444456666444566664444444444
454444444544444466555664454444443b44b3bb4544444445444444454444444544444445444444665556644544444445444444665556646655566445444444
444445444444454466656666444445444b4b3b34444445444444b5b444444544444445444444b5b4666566664444454444444544666566666665666644444544
4444444444444444665566664444444443b34b3444444444444b4b444444444444444444444b4b44665566664444444444444444665566666655666644444444
44444444444444445566556544444444b4b3b3444444444444b34b4444444b4444444b4444b34b44556655654444444444444444556655655566556544444444
44445444444454446665656544445444b4b3b34b44445444b4b35b444b445b444b445b44b4b35b44666565654444544444445444666565656665656544445444
445444444b54b444465566544b54b4444bb3b3b4445444444b344bb44b344b344b344b344b344bb4465566544454444444544444465566544655665444544444
4444444444b4b4bb4455554444b4b4bb4bb3b3b4444444444b34b3b443b4b3b443b4b3b44b34b3b4445555444444444444444444445555444455554444444444
4444444444444444456666444566664444444444444444444444444445666644b4444b4444444444b4444b444444444445666644444444444566664444444444
45444444454444446655566466555664454444444544444445444444665556643b44b3bb454444443b44b3bb4544444466555664454444446655566445444444
444445444444b5b4666566666665666644444544444445444444b5b4666566664b4b3b34444445444b4b3b344444454466656666444445446665666644444544
44444444444b4b4466556666665566664444444444444444444b4b446655666643b34b344444444443b34b344444444466556666444444446655666644444444
4444444444b34b445566556555665565444444444444444444b34b4455665565b4b3b34444444444b4b3b34444444b4455665565444444445566556544444444
44445444b4b35b4466656565666565654444544444445444b4b35b4466656565b4b3b34b44445444b4b3b34b4b445b4466656565444454446665656544445444
445444444b344bb4465566544655665444544444445444444b344bb4465566544bb3b3b4445444444bb3b3b44b344b3446556654445444444655665444544444
444444444b34b3b4445555444455554444444444444444444b34b3b4445555444bb3b3b4444444444bb3b3b443b4b3b444555544444444444455554444444444
44444444456666444566664444444444444444444444444445666644456666444444444444444444456666444566664445666644444444444566664444444444
45444444665556646655566445444444454444444544444466555664665556644544444445444444665556646655566466555664454444446655566445444444
44444544666566666665666644444544444445444444454466656666666566664444b5b4444445446665666666656666666566664444b5b46665666644444544
4444444466556666665566664444444444444444440444440055000606056666400b000400040004665566666655666666556666444b4b446655666644444444
4444444455665565556655654444444444444444407044407700777070705565077077707770777055665565556655655566556544b34b445566556544444444
44445444666565656665656544445444444454444407044070707000707065607000707077707004666565656665656566656565b4b35b446665656544445444
4454444446556654465566544b54b444445444444b507040707077007070665070007770707077044655665446556654465566544b344bb44655665444544444
44444444445555444455554444b4b4bb44444444440704b0707070007770554070707070707070044455554444555544445555444b34b3b44455554444444444
4444444444444444441144114444444444444444407044407070777077704440777070707070777044444444b4444b4444444444b4444b444444444444444444
454444444544444441ff11ff1544444445444444450444440b04000b000444440004040406050004454444443b44b3bb454444443b44b3bb4544444445444444
44444544444445441fef11fef144454444444544444445444b4b3b34444445444444454466656666444445444b4b3b34444445444b4b3b344444454444444544
44444444444444441fef11fef14444444444444444444444400340040044000400040044060500064444444443b34b344444444443b34b344444444444444444
44444444444444441fef11fef1444b4444444444444444440770077077007770777077007070777044444444b4b3b34444444444b4b3b3444444444444444444
44445444444454441fef11fef1445b4444445444444454407000707070700704070070707070700544445444b4b3b34b44445444b4b3b34b4444544444445444
445444444454444441ff11ff1b344b34445444444454444070b07070707007040700707070707704445444444bb3b3b4445444444bb3b3b44454444444544444
444444444444444441ffffff13b4b3b4444444444444444070007070707007040700707070707004444444444bb3b3b4444444444bb3b3b44444444444444444
44444444444444441ff7ff7ff1444444444444444444444407707700707007007770707007707770444444444444444444444444444444444444444444444444
45444444454444441f7dffd7f1444444454444444544444460050064060550640004030b60050004454444444544444445444444454444444544444445444444
44444544444445441fffeefff1444544444445444444454466656666666566664b4b3b3466656666444445444444b5b444444544444445444444454444444544
4444444444444444411ffff1144444444444444444444444665566666655666643b34b346655666644444444444b4b4444444444444444444444444444444444
4444444444444444b1ffffff144444444444444444444b445566556555665565b4b3b344556655654444444444b34b4444444444444444444444444444444444
44445444444454441ffeffeff1445444444454444b445b446665656566656565b4b3b34b6665656544445444b4b35b4444445444444454444444544444445444
44544444445444441ffeffeff154b444445444444b344b3446556654465566544bb3b3b4465566544b54b4444b344bb44b54b444445444444b54b44444544444
44444444444444444111111114b4b4bb4444444443b4b3b444555544445555444bb3b3b44455554444b4b4bb4b34b3b444b4b4bb4444444444b4b4bb44444444
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444
45444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444
44444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444475747744454477747774
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444474744744444474744474
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444474744744444474747774
44445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445444444477744744544474747444
44544444445444444454444444544444445444444454444444544444445444444454444444544444445444444454444444544444445447447774474477747774
44444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444444

__gff__
0800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000001213101000000000000000000013000052131010000000000000000000000300000000000000000000000000000203000000000000000000000000
000000000300000000000000000000000a0a0a0a0e0f00000000000000000000170000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
4040404040565655555656404040404000005252525252525252525200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005246464748464646465200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005246465758464646465200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005246464646464646465200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005245454545457245455200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005245454545454545455200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005245454545454545455200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005245454545454545455200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000005252525255555252525200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000005252525200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
050100000c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c770107700c77010770
5e0a00002b2512b2512b2512b2502b2503f2013f2013f2013f201000003f2503f2503f2513f2513f2513f2513f251000000000035201352011c2012020120201352513525135250352503525035250352503f200
010100003c0403e0403f0403f0403f0403f0403e0403e0403d0403d0403e0403d0403c0403b0403b0403b0403b0403b0403804035040350403604037040390403b0403e0403f0003f0003f000000003f0403b040
490c0020206102161023610256102661026610276102761027610246102361021610206101f6101e6101e6101e610206102161022610236102461024610246102461023610236102461025610256102561025610
010200000c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c2730c273
010200002e6622d6622d6522d6522c6422b6422b64229642286422664223632216321e6221a622176221662213622116220d63209632056120060201602006020660204602080020400201002000020f0020c002
010400120c500105000e50011500185001c5001a5001d5000c500105000c533105430e55311553185331c5431a5531d5530e50018500000000000000000000000000000000000000000000000000000000000000
0004000c115530e553105530c553115530e553105530c5530c500105000e500185000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0120000026500265002650024500235002150023500235001f5001f5001f5001f5001f5001f5001f5001f5001c5001f5002150023500235002350023500000000000026500265002650024500235002150023500
01200000235001f5001f5001f5001f5001f5001f5001f5001f5002450023500215001f5001f5001f5001f5001f5001f5000000000000000000000000000000000000000000000000000000000000000000000000
013e00001850013500135001550017500135001350013500175001350013500155001750017500175000000018500135001350015500175001350013500135001350013500175001550013500135001350000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
051c00001f5641f5601a5641a5601f5641f5602156421560235642356023560235652656426560265602656524564245602356423560215642156024564245602656426560215642156021564215502154021545
0520000026564265602656524564235642156423564235601f5641f5641f5601f5601f5651f5641f5601f5651c5641f5642156423564235602356023565000000000026564265602656524564235642156423564
04201200235601f5641f5641f5601f5601f5651f5641f5601f5652456423564215641f5641f5601f5501f5401f5301f5250000000000000000000000000000000000000000000000000000000000000000000000
003e00001856413564135641556417564135641354413520175641356413564155641756417540175250000018564135641356415564175641356413544135301356413564175641556413564135401352500000
__music__
00 21474344
04 22424344
04 20424344
04 23424344
