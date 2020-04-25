pico-8 cartridge // http://www.pico-8.com
version 21
__lua__
-- stats, for tuning.
-- the font itself is *big*
max_glyph_runs=0
max_run_length=0
zero_starts=0
total_bytes=0

-- figure out the dimensions
-- of the sprite. bottom-left
-- is constant, so we have h
-- and w.
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

-- rle-compress the given 
-- sprite with the given width 
-- and height. returns the runs
-- as a series of numbers to be
-- interpreted as the number of
-- `set` pixels, followed by the 
-- number of `blank` pixels, 
-- followed by the number of 
-- `set` pixels, etc.
function compress(s,w,h)
 -- we can rle encode, i guess
 -- if we have w and h.
 local px=8*flr(s%16)
 local py=8*flr(s/16)
 
 local runs={}
 local run_len=0
 local current=7
 
 for x=0,(w-1) do
  for y=8-h,7 do
   local clr=sget(px+x,py+y)
   if clr==current then
    run_len+=1
   else 
    add(runs,run_len)
    run_len=1
    current=clr
   end
  end
 end
 
 if current~=0 then
  add(runs,run_len)
 end
 
 return runs 
end

goobers=0


-- encode the rle compressed
-- glyph into an array of bytes
function encode(w,h,runs)
 -- convert the run stream to
 -- a count stream, which is
 -- the same *except* each value
 -- in a count stream fits in 3
 -- bits. runs greater than 7
 -- are encoded as a series of
 -- 7s followed by the remainder.
 -- this is not optimal but is
 -- simple and pretty good for 
 -- our input set.
 local count_stream,r={}
 for r in all(runs) do
  while r>=7 do
   add(count_stream, 7)
   r-=7
   goobers+=1
  end
  add(count_stream,r)
 end
 
 -- start writing the output 
 -- byte stream. first the width
 -- and height of the glyph.
 -- high 4 bits: w
 --  low 4 bits: h
 local bytes={}
 add(bytes,w<<4|h)

 -- write the length of the 
 -- count stream to the output 
 -- bytes.
 add(bytes,#count_stream)
 
 -- 3 bits/run,8 runs in 24bit
 -- value.
 --
 --    2         1  
 -- 321098765432109876543210
 -- aaabbbcccdddeeefffggghhh
 -- xxxxxxxxyyyyyyyyzzzzzzzz
 --
 local i=1
 while i<=#count_stream do
  -- accumulate 8 3bit numbers 
  -- into 1 24bit integer, and
  -- count the number of bits
  -- we actually emit.
  local acc,bitc,j=0,0
  for j=1,8 do
   acc <<= 3
   if i<=#count_stream then
    acc |= count_stream[i]>>16
    i+=1
    bitc+=3
   end
  end
  
  -- figure out how many bytes 
  -- we need to emit: for the 
  -- last set of counts we can
  -- get away with fewer than 3.
  local bytec=ceil(bitc/8)
  -- print("+++ "..bitc.." "..bytec.." "..i.." "..#count_stream)
  
  -- unpack 1 24bit integer into
  -- 3 8bit bytes 
  for j=1,bytec do
   add(bytes, acc&0x00ff)
   acc=acc<<8
  end
 end
 
 return bytes
end

function dumbo(s,w,h)
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

function dbg(x)
 --print(x)
end

function build_glyphs(s,e)
 local glyphs={}
 for i=s,e do
  r=analyze(i)
  dbg(i..": "..r.w.."x"..r.h)
  runs=compress(i, r.w, r.h)

  add(glyphs,{
   s=i,
   w=r.w,
   h=r.h,
   runs=runs
  })
 end
 return glyphs
end

glyphs=build_glyphs(1,66)
for g in all(glyphs) do
 -- keep track: zero starts are
 -- wasteful so we want to 
 -- minimize them.
 if g.runs[1]==0 then
  zero_starts+=1
 end
 
 max_glyph_runs=max(
  #g.runs,
  max_glyph_runs)
 
 for run_i=1,#runs do
  max_run_length=max(
   g.runs[run_i],
   max_run_length)
 end
 
 rl=""
 for run_i=1,#g.runs do
  rl=rl.." "..g.runs[run_i]
  if #rl>30 then
   dbg(rl)
   rl=""
  end
 end
 if #rl>0 then
  dbg(rl)
 end
  
 bytes=encode(g.w,g.h,g.runs)
 dbg(" "..#runs.." runs "..#bytes.." bytes")
 total_bytes+=#bytes
 
-- if i%5==0 then
--  repeat
--  until btn(🅾️)
-- end
end

-- 
print ""
print("max glyph runs: "..max_glyph_runs)
print("max run length: "..max_run_length)
print("   zero starts: "..zero_starts.."/66")
print("   total bytes: "..total_bytes)
print("       goobers: "..goobers)
-->8
-- huffman encoding

-- bubble sort of nodes by freq
function sort_by_freq(nodes)
 local changed=true
 while changed do
  changed=false
  for i=1,#nodes-1 do
   if nodes[i].freq>nodes[i+1].freq then
    local tmp=nodes[i]
    nodes[i]=nodes[i+1]
    nodes[i+1]=tmp
    changed = true
   end
  end
 end
end

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

-- return a new array that has
-- v appended to it.
function cons(a,v)
 local n={}
 if a~=nil then
  for i=1,#a do
   n[i]=a[i]
  end
 end
 add(n,v)
 return n
end

-- build the encoding table for
-- the given huffman tree and 
-- path
function build_table(node,path)
 if node.left~=nil then
  return merge(
   build_table(node.left,cons(path,0)),
   build_table(node.right,cons(path,1)))
 else
  local result={}
  result[node.val]=path
  return result
 end
end

function print_table(tbl)
 for k,v in pairs(tbl) do
  local bitstr=""
  for b in all(v) do
   bitstr=bitstr..b
  end
  print("  "..k.." "..bitstr)
 end
end

function count(freq,r)
 if freq[r]==nil then
  freq[r]=0
 end
 freq[r] = freq[r]+1
end

function new_bs()
 return {bytes={},acc=0,bits=0}
end

function write_bs(bs,bits)
 for bit in all(bits) do
  bs.acc=bs.acc<<1|bit
  bs.bits=bs.bits+1
  if bs.bits==8 then
   add(bs.bytes,bs.acc)
   bs.bits=0
   bs.acc=0
  end
 end
end

function flush_bs(bs)
 if bs.bits>0 then
  bs.acc=bs.acc<<(8-bs.bits)
  add(bs.bytes,bs.acc)
 end
 return bs.bytes
end

function huffman_code(glyphs)
 -- compute the run freq of the
 -- glyphs
 local freq={}
 for g in all(glyphs) do
  count(freq,g.w)
  count(freq,g.h)
  count(freq,#g.runs) --?
  for r in all(g.runs) do
   count(freq,r)
  end
 end
 
 -- build the initial node set
 local nodes={}
 for k,v in pairs(freq) do
  add(nodes,{val=k,freq=v})
 end
 
 -- build the huffman tree
 while #nodes>1 do
  sort_by_freq(nodes)
  
  -- make a new inner node from
  -- the two smallest freq nodes
  local inner={
   left=nodes[1],
   right=nodes[2],
   freq=nodes[1].freq+nodes[2].freq
  }
  
  -- replace the two smallest 
  -- freq nodes with the new inner
  -- node
  del(nodes,nodes[2])
  nodes[1]=inner
 end

 local tbl=build_table(nodes[1])
 print_table(tbl)

 -- compress the runs with the
 -- table.
 for g in all(glyphs) do
  -- todo: fewer bits for runs
  local bs=new_bs()
  write_bs(bs,tbl[g.w])
  write_bs(bs,tbl[g.h])
  write_bs(bs,tbl[#g.runs])
  for r in all(g.runs) do
   write_bs(bs,tbl[r])
  end
  g.compressed=flush_bs(bs)
 end
 
 local total=0
 for g in all(glyphs) do
  total+=#g.compressed
  --print(g.s.." "..#g.runs.." "..#g.compressed)
 end
 print("total: "..total)
 print(#tbl)
end

huffman_code(glyphs)

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
00700000000000007000000070000000007000007000000070000000000000000000000000000000000000000000000000000000000000000700000000000000
07070000077000007000000000000000000000007000000070000000000000000000000000000000000000000000000000000000000000000700000000000000
07000000700700007770000070000000007000007007000070000000070700007070000007700000077000000770000070700000077000007770000070070000
77700000700700007007000070000000007000007007000070000000707070007707000070070000700700007007000077070000700700000700000070070000
07000000077700007007000070000000007000007770000070000000707070007007000070070000700700007007000070070000070000000700000070070000
07000000000700007007000070000000007000007007000070000000700070007007000070070000777000000777000070000000007000000700000070070000
07000000700700007007000070000000707000007007000070000000700070007007000070070000700000000007000070000000700700000700000070070000
07000000077000007007000070000000070000007007000007000000700070007007000007700000700000000007000070000000077000000700000007700000
00000000000000000000000000000000000000000770000007000000077000000770000070700000777700000770000077770000077000000770000070000000
00000000000000000000000000000000000000007007000077000000700700007007000070700000700000007007000000070000700700007007000070000000
70007000700070007000700070070000777700007007000007000000000700000007000070700000700000007000000000070000700700007007000070000000
70007000700070000707000070070000000700007077000007000000000700000070000077770000777000007770000000700000077000000777000070000000
07070000707070000070000070070000007000007707000007000000007000000007000000700000000700007007000007000000700700000007000070000000
07070000707070000070000007770000070000007007000007000000070000000007000000700000000700007007000070000000700700000007000070000000
00700000707070000707000000070000700000007007000007000000700000007007000000700000700700007007000070000000700700000007000000000000
00700000070700007000700077700000777700000770000077700000777700000770000000700000077000000770000070000000077000000007000070000000
07770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000700000007070700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
