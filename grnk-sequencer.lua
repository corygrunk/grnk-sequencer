-- GRNK GRID
-- 
-- todos: move engine selection to param page
-- todos: save patterns to preset
-- Norns UI!!!!!!


g = grid.connect() -- if no argument is provided, defaults to port 1

engine.name = 'PolyPerc'

lattice = require('lattice')
MusicUtil = require('musicutil')
TAB = require('tabutil')

scale_names = {}

engines = {}
engines[1] = 'engine'
engines[2] = 'crow 1+2'
engines[3] = 'crow 3+4'
engines[4] = 'jf'

notes = {} -- this is the table that holds the scales notes
note_queue = {}
note_queue_counter = 0
note_name = '__'

playing = true

current_track = 1 -- 1,2,3,4
eng_cut = 1200
eng_rel = 1.0
crow_attack = 0.001

function init()

  engine.cutoff(eng_cut)
  engine.release(eng_rel)


  crow.output[2].action = "ar(dyn{ attack = 0.001 }, dyn{ decay = 0.1 }, 10, 'logarithmic')" -- linear sine logarithmic exponential
  crow.output[4].action = "pulse(0.001, 8)" -- linear sine logarithmic exponential

  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, MusicUtil.SCALES[i].name)
  end

  params:add_separator("GRNK LIVE")
  
  -- setting root notes using params
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 24, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end} -- by employing build_scale() here, we update the scale

  -- setting scale type using params
  params:add{type = "option", id = "scale", name = "scale",
    options = scale_names, default = 5,
    action = function() build_scale() end} -- by employing build_scale() here, we update the scale

  build_scale() -- builds initial scale


  grid_connected = g.device ~= nil and true or false -- ternary operator, eg. http://lua-users.org/wiki/TernaryOperator
  led_intensity = 15 -- scales LED intensity

  rec_state = false
  delete_pattern_mode = false
  seq_add_note_mode = false
  edit_track_mode = false
  edit_loop_mode = false
  alt_seq_offset_edit_mode = false
  sync_patterns_ready = false

  clock_div_options = {}
  clock_div_options[1] = 1
  clock_div_options[2] = 1/2
  clock_div_options[3] = 1/4
  clock_div_options[4] = 1/8
  clock_div_options[5] = 1/16
  clock_div_options[6] = 1/32

  row_max = 8 -- This shouldn't change it is the UI row length. It is used for UI maths

  note_queue[1] = params:get("root_note") + 32

  tracks = {}
  for i = 1, 4 do
    tracks[i] = {
      source = 'engine',
      pos = 0,
      offset_pos = 0,
      step_counter = 0,
      pattern = {
        clock_div = 1/16,
        offsets_clock_div = 1/8,
        prob = 100,
        length = 16,
        offset_length = 6,
        gates = {},
        notes = {},
        note_lengths = {},
        offsets = {}
      },
      saves = {}
    }
  end

  for i = 1, TAB.count(tracks) do
    for n = 1, tracks[i].pattern.length do
      tracks[i].pattern.gates[n] = 0 -- start with 0's in every step
      tracks[i].pattern.notes[n] = note_queue[1] -- start with root note in every step
      tracks[i].pattern.note_lengths[n] = eng_rel -- start with the engine release in every step
      if n <= tracks[i].pattern.offset_length then
        tracks[i].pattern.offsets[n] = 0 -- start no offsets
      end
    end
  end

  seq_lattice = lattice:new{
    auto = true,
    meter = 4,
    ppqn = 96
  }

  -- LATICE PATTERNS - TRACK 01
  track_one = seq_lattice:new_pattern{
    action = function(t) track_01_step() end,
    division = tracks[1].pattern.clock_div,
    enabled = true
  }
  track_one_offset = seq_lattice:new_pattern{
    action = function(t) track_01_offset_step() end,
    division = tracks[1].pattern.offsets_clock_div,
    enabled = true
  }
  -- LATICE PATTERNS - TRACK 02
  track_two = seq_lattice:new_pattern{
    action = function(t) track_02_step() end,
    division = tracks[2].pattern.clock_div,
    enabled = true
  }
  track_two_offset = seq_lattice:new_pattern{
    action = function(t) track_02_offset_step() end,
    division = tracks[2].pattern.offsets_clock_div,
    enabled = true
  }
  -- LATICE PATTERNS - TRACK 03
  track_three = seq_lattice:new_pattern{
    action = function(t) track_03_step() end,
    division = tracks[3].pattern.clock_div,
    enabled = true
  }
  track_three_offset = seq_lattice:new_pattern{
    action = function(t) track_03_offset_step() end,
    division = tracks[3].pattern.offsets_clock_div,
    enabled = true
  }
  -- LATICE PATTERNS - TRACK 04
  track_four = seq_lattice:new_pattern{
    action = function(t) track_04_step() end,
    division = tracks[4].pattern.clock_div,
    enabled = true
  }
  track_four_offset = seq_lattice:new_pattern{
    action = function(t) track_04_offset_step() end,
    division = tracks[4].pattern.offsets_clock_div,
    enabled = true
  }


  seq_lattice:start()

  redraw_clock_id = clock.run(redraw_clock)

  grid_dirty = true -- use flags to keep track of whether hardware needs to be redrawn
  screen_dirty = true
end

function build_scale()
  notes = MusicUtil.generate_scale(params:get("root_note"), params:get("scale"), 6)
  for i = 1, 64 do
    table.insert(notes, notes[i])
  end
end

function redraw_clock()
  while true do
    clock.sleep(1/15)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end

-- TRACK 01 STEPS and OFFSET
function track_01_offset_step()
  tracks[1].offset_pos = util.wrap(tracks[1].offset_pos+1,1,tracks[1].pattern.offset_length) -- progress the alt sequence
end
function track_01_step()
  if sync_patterns_ready == true and current_track == 1 then
    tracks[1].pos = 0
    tracks[1].offset_pos = 0
    sync_patterns_ready = false
  end
  engine.cutoff(eng_cut)
  tracks[1].pos = util.wrap(tracks[1].pos+1,1,tracks[1].pattern.length) -- progress the sequence
  if tracks[1].pattern.gates[tracks[1].pos] == 1 then
    local rand = math.random(100)
    if tracks[1].pattern.prob >= rand then
      if tracks[1].pattern.notes[tracks[1].pos] ~= nil then
        if tracks[1].pattern.offsets[tracks[1].offset_pos] == nil then -- fixing pattern sync bug
          tracks[1].offset_pos = 0
        end
        play_note(
          tracks[1].source,
          tracks[1].pattern.notes[tracks[1].pos],
          tracks[1].pattern.note_lengths[tracks[1].pos],
          tracks[1].pattern.offsets[tracks[1].offset_pos]
        )
      end
    end
  end
  grid_dirty = true -- redraw grid!
  if screen_dirty then redraw() end
  if grid_dirty then grid_redraw() end
end

-- TRACK 02 STEPS and OFFSETS
function track_02_offset_step()
  tracks[2].offset_pos = util.wrap(tracks[2].offset_pos+1,1,tracks[2].pattern.offset_length) -- progress the alt sequence
end
function track_02_step()
  if sync_patterns_ready == true and current_track == 2 then
    tracks[2].pos = 0
    tracks[2].offset_pos = 0
    sync_patterns_ready = false
  end
  engine.cutoff(eng_cut)
  tracks[2].pos = util.wrap(tracks[2].pos+1,1,tracks[2].pattern.length) -- progress the sequence
  if tracks[2].pattern.gates[tracks[2].pos] == 1 then
    local rand = math.random(100)
    if tracks[2].pattern.prob >= rand then
      if tracks[2].pattern.notes[tracks[2].pos] ~= nil then
        if tracks[2].pattern.offsets[tracks[2].offset_pos] == nil then -- fixing pattern sync bug
          tracks[2].offset_pos = 0
        end
        play_note(
          tracks[2].source,
          tracks[2].pattern.notes[tracks[2].pos],
          tracks[2].pattern.note_lengths[tracks[2].pos],
          tracks[2].pattern.offsets[tracks[2].offset_pos]
        )
      end
    end
  end
  grid_dirty = true -- redraw grid!
  if screen_dirty then redraw() end
  if grid_dirty then grid_redraw() end
end

-- TRACK 03 STEPS and OFFSETS
function track_03_offset_step()
  tracks[3].offset_pos = util.wrap(tracks[3].offset_pos+1,1,tracks[3].pattern.offset_length) -- progress the alt sequence
end
function track_03_step()
  if sync_patterns_ready == true and current_track == 3 then
    tracks[3].pos = 0
    tracks[3].offset_pos = 0
    sync_patterns_ready = false
  end 
  engine.cutoff(eng_cut)
  tracks[3].pos = util.wrap(tracks[3].pos+1,1,tracks[3].pattern.length) -- progress the sequence
  if tracks[3].pattern.gates[tracks[3].pos] == 1 then
    local rand = math.random(100)
    if tracks[3].pattern.prob >= rand then
      if tracks[3].pattern.notes[tracks[3].pos] ~= nil then
        if tracks[3].pattern.offsets[tracks[3].offset_pos] == nil then -- fixing pattern sync bug
          tracks[3].offset_pos = 0
        end
        play_note(
          tracks[3].source,
          tracks[3].pattern.notes[tracks[3].pos],
          tracks[3].pattern.note_lengths[tracks[3].pos],
          tracks[3].pattern.offsets[tracks[3].offset_pos]
        )
      end
    end
  end
  grid_dirty = true -- redraw grid!
  if screen_dirty then redraw() end
  if grid_dirty then grid_redraw() end
end

-- TRACK 04 STEPS and OFFSETS
function track_04_offset_step()
  tracks[4].offset_pos = util.wrap(tracks[4].offset_pos+1,1,tracks[4].pattern.offset_length) -- progress the alt sequence
end
function track_04_step()
  if sync_patterns_ready == true and current_track == 4 then
    tracks[4].pos = 0
    tracks[4].offset_pos = 0
    sync_patterns_ready = false
  end 
  engine.cutoff(eng_cut)
  tracks[4].pos = util.wrap(tracks[4].pos+1,1,tracks[4].pattern.length) -- progress the sequence
  if tracks[4].pattern.gates[tracks[4].pos] == 1 then
    local rand = math.random(100)
    if tracks[4].pattern.prob >= rand then
      if tracks[4].pattern.notes[tracks[4].pos] ~= nil then
        if tracks[4].pattern.offsets[tracks[4].offset_pos] == nil then -- fixing pattern sync bug
          tracks[4].offset_pos = 0
        end
        play_note(
          tracks[4].source,
          tracks[4].pattern.notes[tracks[4].pos],
          tracks[4].pattern.note_lengths[tracks[4].pos],
          tracks[4].pattern.offsets[tracks[4].offset_pos]
        )
      end
    end
  end
  grid_dirty = true -- redraw grid!
  if screen_dirty then redraw() end
  if grid_dirty then grid_redraw() end
end

function play_note(source,midi_note_num,note_length,note_offset)
  if note_offset == nil then 
    note_offset = 0 
  end
  if type(midi_note_num) ~= 'table' then
    local container = midi_note_num
    midi_note_num = {}
    midi_note_num[1] = container
  end
  if source == "engine" then
    for i = 1, TAB.count(midi_note_num) do
      engine.release(note_length)
      engine.hz(MusicUtil.note_num_to_freq(midi_note_num[i] + note_offset))
    end
  elseif source == "crow 1+2" then
    crow.output[1].volts = (midi_note_num[1] + note_offset)/12
    crow.output[2].dyn.decay = note_length
    crow.output[2]()
  elseif source == "crow 3+4" then
    crow.output[3].volts = (midi_note_num[1] + note_offset)/12
    crow.output[4]()
  elseif source == "jf" then
    for i = 1, TAB.count(midi_note_num) do
      crow.ii.jf.play_note((midi_note_num[i] + note_offset - 60)/12, 4)
    end
  end
  note_name = midi_note_num[1]
  -- for i = 1, TAB.count(midi_note_num) do
  --   -- print(midi_note_num[i])
  -- end
  redraw()
end

function save_pattern(save_slot)
  tracks[current_track].saves[save_slot] = {}
  tracks[current_track].saves[save_slot].clock_div = tracks[current_track].pattern.clock_div
  tracks[current_track].saves[save_slot].offsets_clock_div = tracks[current_track].pattern.offsets_clock_div
  tracks[current_track].saves[save_slot].prob = tracks[current_track].pattern.prob
  tracks[current_track].saves[save_slot].length = tracks[current_track].pattern.length
  tracks[current_track].saves[save_slot].offset_length = tracks[current_track].pattern.offset_length
  tracks[current_track].saves[save_slot].gates = {}
  tracks[current_track].saves[save_slot].notes = {}
  tracks[current_track].saves[save_slot].note_lengths = {}
  tracks[current_track].saves[save_slot].note_lengths = {}
  tracks[current_track].saves[save_slot].offsets = {}
  for i = 1, tracks[current_track].pattern.length do
    tracks[current_track].saves[save_slot].gates[i] = tracks[current_track].pattern.gates[i]
    tracks[current_track].saves[save_slot].notes[i] = tracks[current_track].pattern.notes[i]
    tracks[current_track].saves[save_slot].note_lengths[i] = tracks[current_track].pattern.note_lengths[i]
  end
  for i = 1, tracks[current_track].pattern.offset_length do
    tracks[current_track].saves[save_slot].offsets[i] = tracks[current_track].pattern.offsets[i]
  end
  print('pattern saved')
end

function load_pattern(load_slot)
  tracks[current_track].pattern = {}
  tracks[current_track].pattern.clock_div = tracks[current_track].saves[load_slot].clock_div
  tracks[current_track].pattern.offsets_clock_div = tracks[current_track].saves[load_slot].offsets_clock_div
  tracks[current_track].pattern.prob = tracks[current_track].saves[load_slot].prob
  tracks[current_track].pattern.length = tracks[current_track].saves[load_slot].length
  tracks[current_track].pattern.offset_length = tracks[current_track].saves[load_slot].offset_length
  tracks[current_track].pattern.gates = {}
  tracks[current_track].pattern.notes = {}
  tracks[current_track].pattern.note_lengths = {}
  tracks[current_track].pattern.note_lengths = {}
  tracks[current_track].pattern.offsets = {}
  for i = 1, tracks[current_track].saves[load_slot].length do
    tracks[current_track].pattern.gates[i] = tracks[current_track].saves[load_slot].gates[i]
    tracks[current_track].pattern.notes[i] = tracks[current_track].saves[load_slot].notes[i]
    tracks[current_track].pattern.note_lengths[i] = tracks[current_track].saves[load_slot].note_lengths[i]
  end
  for i = 1, tracks[current_track].saves[load_slot].offset_length do
    tracks[current_track].pattern.offsets[i] = tracks[current_track].saves[load_slot].offsets[i]
  end
  print('pattern loaded')
end

function delete_pattern(pattern_slot)
  tracks[current_track].saves[pattern_slot] = nil
  print('pattern deleted')
end

function grid_redraw()
  if grid_connected then -- only redraw if there's a grid connected
    g:all(0) -- turn all the LEDs off

    local count = 0 -- counting each iteration of the for loop
    local row_counter = 1 -- counting when to change rows

    -- light up patterns and clock divs
    if edit_track_mode == true then
      if delete_pattern_mode == true then g:led(8,1,8) end
      for x = 1, 6 do
        local led_val = 3
        if tracks[current_track].saves[x] ~= nil then
          led_val = 8
        end
        g:led(x,1,led_val)
      end
      for i = 1, 4 do
        for n = 1, TAB.count(clock_div_options) do
          local led_val = 3
          if tracks[current_track].pattern.clock_div == clock_div_options[n] then
            led_val = 8
          end
          g:led(n,2,led_val)
        end
      end
      for i = 1, 4 do
        for j = 1, TAB.count(clock_div_options) do
          local led_val = 3
          if tracks[current_track].pattern.offsets_clock_div == clock_div_options[j] then
            led_val = 8
          end
          g:led(j,6,led_val)
        end
      end
    end

    -- light up sequence
    if edit_track_mode == false then
      for n = 1, tracks[current_track].pattern.length do
        local led_val = 3
        count = count + 1
        if count > row_max then
          row_counter = row_counter + 1
          count = 1
        end
        if tracks[current_track].pattern.gates[n] == 1 then
          led_val = 8
        end
        if n == tracks[current_track].pos then
          led_val = 15
        end
        g:led(count,row_counter,led_val)
        led_val = 3
      end
    end

    -- light up offsets sequence
    for x = 1, tracks[current_track].pattern.offset_length do
      g:led(x,5,3)
      if tracks[current_track].pattern.offsets[x] ~= 0 then
        g:led(x,5,8)
      end
      if tracks[current_track].offset_pos == x then
        g:led(x,5,15)
      end
    end

    -- light up live pads
    if alt_seq_offset_edit_mode == false then
      for x = 9,16 do
        for y = 1,8 do
          g:led(x,y,3)
          -- manually lighting roots
          g:led(9,1,6)
          g:led(16,1,6)
          g:led(12,2,6)
          g:led(15,3,6)
          g:led(11,4,6)
          g:led(14,5,6)
          g:led(10,6,6)
          g:led(13,7,6)
          g:led(9,8,6)
          g:led(16,8,6)
        end
      end
    end

    -- light up offsets sequence offsets
    if alt_seq_offset_edit_mode == true then
      for x = 9,8 + tracks[current_track].pattern.offset_length do
        for y = 1,8 do
          g:led(x,y,3)
          local offset = tracks[current_track].pattern.offsets[x - 8]
          -- TODO Better
          -- -octave = -8
          -- -fifth = -5
          -- offsets = 0
          -- third = 3
          -- fourth = 4
          -- fifth = 5
          -- octave = 8
          if offset ~= nil then
            g:led(x,5 - offset,8)
          end
        end
      end
    end

    -- light up sequence note played pads - first check if there's a note at the position
    if alt_seq_offset_edit_mode == false and tracks[current_track].pattern.gates[tracks[current_track].pos] == 1 then
      for x = 9,16 do
        for y = 1,8 do
          -- make a container for the notes
          local note_num = {}
          -- if the note is not a table, make it one and fill it with the note(s)
          if type(tracks[current_track].pattern.notes[tracks[current_track].pos]) ~= 'table' then
            note_num[1] = tracks[current_track].pattern.notes[tracks[current_track].pos]
          else
            for n = 1, TAB.count(tracks[current_track].pattern.notes[tracks[current_track].pos]) do
              note_num[n] = tracks[current_track].pattern.notes[tracks[current_track].pos][n]
            end
          end
          -- sweet, note_num has all the notes for that step
          -- is this pad a note in that step? Compare note to the note on the step and light the pad.
          -- NOT QUITE WORKING
          local pad_counter = 29 -- this keeps the notes in order from row to row in fourths
          for p = 1, 8 do -- p is the pad 1-8 in row y
            if y == p then
              for i = 1, 8 do 
                for n = 1, TAB.count(note_num) do 
                  if notes[i + pad_counter] == note_num[n] then
                    g:led(i + 8,y,12)
                  end
                end 
              end
            end
            pad_counter = pad_counter - 3
          end
        end
      end
    end

    -- light up track select
    for x = 1, TAB.count(tracks) do
      local track_lights = 3
      if x == current_track then track_lights = 8 else track_lights = 3 end
      g:led(x,7,track_lights)
    end

    -- light up record pad
    if rec_state == true then g:led(1,8,8) end
    if rec_state == false then g:led(1,8,3) end

    -- light up random notes pad
    g:led(2,8,3)

    -- light up reset notes pad
    g:led(3,8,3)

    -- light up random length pad
    g:led(5,8,3)

    -- light up reset note lengths
    g:led(6,8,3)

    -- light up loop edit
    g:led(8,7,3)

    -- light up pattern/offset sync
    g:led(8,8,3)

    g:intensity(led_intensity) -- change intensity
    g:refresh() -- refresh the LEDs
  end
  grid_dirty = false -- reset the flag because changes have been committed
end


function live_pad(note,record,z_state)
  if z_state == 1 then -- note pressed
    note_queue_counter = note_queue_counter + 1
    if note_queue_counter == 1 then -- first new note
      note_queue = {}
      note_queue[note_queue_counter] = note
    elseif note_queue_counter > 1 then -- add additional notes
      note_queue[note_queue_counter] = note
    end
    play_note(tracks[current_track].source,note,eng_rel) -- play the note
    
    if record == true then
      tracks[current_track].pattern.gates[tracks[current_track].pos] = 1
      tracks[current_track].pattern.notes[tracks[current_track].pos] = note
      tracks[current_track].pattern.note_lengths[tracks[current_track].pos] = eng_rel
    end
  else -- note up
    note_queue_counter = note_queue_counter - 1 -- remove each added note to reset the counter
  end
end

function get_seq_button(x,y)
  local multiplier = 0 -- terrible variable name. maths is getting above my head.
  if y == 1 then multiplier = -1 end
  if y == 2 then multiplier = 6 end
  if y == 3 then multiplier = 13 end
  if y == 4 then multiplier = 20 end
  local results = multiplier + y + x
  if results <= tracks[current_track].pattern.length then return results end
end

function shuffle(t)
  local tbl = {}
  for i = 1, #t do
    tbl[i] = t[i]
  end
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end


function g.key(x,y,z)
  -- print(x .. ',' .. y .. ',' .. z)

  -- live record
  if x == 1 and y == 8 and z == 1 then
    if rec_state == false then
      rec_state = true
    else
      rec_state = false
    end
    grid_dirty = true
  end
  -- if x == 1 and y == 8 and z == 0 then
  --   rec_state = false
  -- end

  -- randomize sequence
  if x == 2 and y == 8 and z == 1 then
    -- shuffle existing notes and gates
    -- tracks[current_track].pattern.gates = shuffle(tracks[current_track].pattern.gates)
    -- tracks[current_track].pattern.notes = shuffle(tracks[current_track].pattern.notes)
    -- really random
    for i = 1, tracks[current_track].pattern.length do
      tracks[current_track].pattern.gates[i] = math.random(0,1)
      tracks[current_track].pattern.notes[i] = notes[math.random(24,32)]
    end
  end

  -- clear sequence
  if x == 3 and y == 8 and z == 1 then
    for i = 1, tracks[current_track].pattern.length do
      tracks[current_track].pattern.gates[i] = 0
      tracks[current_track].pattern.notes[i] = note_queue
    end
  end

  -- randomize note lengths
  if x == 5 and y == 8 and z == 1 then
    for i = 1, tracks[current_track].pattern.length do
      tracks[current_track].pattern.note_lengths[i] = math.random(1,7) * 0.1
    end
  end

  -- reset note lengths
  if x == 6 and y == 8 and z == 1 then
    for i = 1, tracks[current_track].pattern.length do
      tracks[current_track].pattern.note_lengths[i] = eng_rel
    end
  end

  -- sync current / all patterns and offsets
  if x == 8 and y == 8 and z == 1 then
    sync_patterns_ready = true
  end

  -- track select / pattern select
  if x <= 4 and y == 7 and z == 1 then
    if current_track ~= x then -- if the current track is selected show the patterns
      current_track = x
    else
      edit_track_mode = true
    end
    redraw()
    grid_redraw()
  end
  if x <= 4 and y == 7 and z == 0 then
    edit_track_mode = false
    grid_redraw()
  end

  -- pattern select / load / delete
  if z == 1 and y == 1 and x <= 6 and edit_track_mode == true then
    if delete_pattern_mode == false then
      if tracks[current_track].saves[x] == nil then
        save_pattern(x)
      else
        load_pattern(x)
      end      
    else
      delete_pattern(x)
    end
  end

  -- edit clock div - gawd this looks like a refactor is in order
  if z == 1 and y == 2 and x <= TAB.count(clock_div_options) and edit_track_mode == true then
    -- TRACK 1
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 1 then 
        track_one:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.clock_div = clock_div_options[i]
      end
    end
    -- TRACK 2
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 2 then 
        track_two:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.clock_div = clock_div_options[i]
      end
    end
    -- TRACK 3
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 3 then 
        track_three:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.clock_div = clock_div_options[i]
      end
    end
    -- TRACK 4
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 4 then 
        track_four:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.clock_div = clock_div_options[i]
      end
    end
  end

  -- edit offsets clock div - gawd this looks like a refactor is in order
  if z == 1 and y == 6 and x <= TAB.count(clock_div_options) and edit_track_mode == true then
    -- TRACK 1
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 1 then 
        track_one_offset:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.offsets_clock_div = clock_div_options[i]
      end
    end
    -- TRACK 2
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 2 then 
        track_two_offset:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.offsets_clock_div = clock_div_options[i]
      end
    end
    -- TRACK 3
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 3 then 
        track_three_offset:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.offsets_clock_div = clock_div_options[i]
      end
    end
    -- TRACK 4
    for i = 1, TAB.count(clock_div_options) do
      if x == i and current_track == 4 then 
        track_four_offset:set_division(clock_div_options[i]) 
        tracks[current_track].pattern.offsets_clock_div = clock_div_options[i]
      end
    end
  end

  -- delete a pattern
  -- TODO: MOVE BUTTON FOR ERGONOMICS
  if z == 1 and y == 1 and x == 8 and edit_track_mode == true then
    delete_pattern_mode = true
  elseif z == 0 and y == 1 and x == 8 and edit_track_mode == true then
    delete_pattern_mode = false
  end

  if z == 1 and x == 8 and y == 7 then
    edit_loop_mode = true
  end
  if z == 0 and x == 8 and y == 7 then
    edit_loop_mode = false
  end

  if edit_track_mode == false and edit_loop_mode == true then
    if z == 1 and x <= 8 and y <= 4 then
      local prev_length = tracks[current_track].pattern.length
      -- this is stupid but I'm tired and don't want to figure out the equation.
      local mult = 0
      if y == 1 then mult = 0 end
      if y == 2 then mult = 8 end
      if y == 3 then mult = 16 end
      if y == 4 then mult = 24 end
      local new_length = x + mult
      tracks[current_track].pattern.length = new_length
      if tracks[current_track].pattern.length > prev_length then -- if the new length is longer, add some date/notes
        for i = 1, tracks[current_track].pattern.length do
          if tracks[current_track].pattern.gates[i] == nil then
            tracks[current_track].pattern.gates[i] = 0
            tracks[current_track].pattern.notes[i] = 60
            tracks[current_track].pattern.note_lengths[i] = eng_rel
          end
        end
      end
    end
  end

  if alt_seq_offset_edit_mode == false and edit_loop_mode == true then
    if z == 1 and x <= 8 and y == 5 then
      print('click')
      local prev_alt_length = tracks[current_track].pattern.offset_length
      local new_length = x
      if new_length > prev_alt_length then
        for i = 1, new_length do
          if tracks[current_track].pattern.offsets[i] == nil then
            tracks[current_track].pattern.offsets[i] = 0
          end
        end
      end
      tracks[current_track].pattern.offset_length = new_length
    end
  end

  -- sequencer buttons down
  if edit_track_mode == false and edit_loop_mode == false then
    if z == 1 and x <= 8 and y <= 4 then
      -- print('seq button down')
      seq_add_note_mode = true
      -- print('seq_add_note_mode = ' .. tostring(seq_add_note_mode))
    end
  end

  -- sequencer buttons up
  if edit_track_mode == false  and edit_loop_mode == false then
    if z == 0 and x <= 8 and y <= 4 and edit_track_mode == false then
      -- print('seq button up')
      if get_seq_button(x,y) ~= nil then
        local button_number = get_seq_button(x,y)
        if tracks[current_track].pattern.gates[button_number] == 1 then
          tracks[current_track].pattern.gates[button_number] = 0
        else
          tracks[current_track].pattern.notes[button_number] = note_queue
          tracks[current_track].pattern.note_lengths[button_number] = eng_rel
          tracks[current_track].pattern.gates[button_number] = 1
        end
        grid_redraw()
        seq_add_note_mode = false
      end
      -- print('seq_add_note_mode = ' .. tostring(seq_add_note_mode))
    end
  end

  -- offset sequence button down
  if z == 1 and x <= 8 and y == 5 and edit_loop_mode == false then
    -- print('offset seq button down')
    alt_seq_offset_edit_mode = true
  end

  -- offset sequence button up
  if z == 0 and x <= 8 and y == 5 and edit_loop_mode == false then
    -- print('offset seq button up')
    alt_seq_offset_edit_mode = false
  end

  -- offset button down
  if alt_seq_offset_edit_mode == true then
    if z == 1 and x > 8 then
      tracks[current_track].pattern.offsets[x - 8] = 5 - y
      grid_redraw()
    end
  end

  -- live play buttons
  if alt_seq_offset_edit_mode == false then
    for i = 1, 8 do
      if z == 1 then
        if y == 8 then if x == i + 8 then live_pad(notes[i + 8], rec_state, z) end end
        if y == 7 then if x == i + 8 then live_pad(notes[i + 11], rec_state, z) end end
        if y == 6 then if x == i + 8 then live_pad(notes[i + 14], rec_state, z) end end
        if y == 5 then if x == i + 8 then live_pad(notes[i + 17], rec_state, z) end end
        if y == 4 then if x == i + 8 then live_pad(notes[i + 20], rec_state, z) end end
        if y == 3 then if x == i + 8 then live_pad(notes[i + 23], rec_state, z) end end
        if y == 2 then if x == i + 8 then live_pad(notes[i + 26], rec_state, z) end end
        if y == 1 then if x == i + 8 then live_pad(notes[i + 29], rec_state, z) end end
      else
        if y == 8 then if x == i + 8 then live_pad(notes[i + 8], rec_state, z) end end
        if y == 7 then if x == i + 8 then live_pad(notes[i + 11], rec_state, z) end end
        if y == 6 then if x == i + 8 then live_pad(notes[i + 14], rec_state, z) end end
        if y == 5 then if x == i + 8 then live_pad(notes[i + 17], rec_state, z) end end
        if y == 4 then if x == i + 8 then live_pad(notes[i + 20], rec_state, z) end end
        if y == 3 then if x == i + 8 then live_pad(notes[i + 23], rec_state, z) end end
        if y == 2 then if x == i + 8 then live_pad(notes[i + 26], rec_state, z) end end
        if y == 1 then if x == i + 8 then live_pad(notes[i + 29], rec_state, z) end end
      end
    end
  end
end


function redraw()
  screen.clear() -- clear screen
  screen.move(0,10)
  screen.text('WIP GRNK LIVE')
  screen.move(120,10)
  local engine_text = tracks[current_track].source
  if engine_text == 'engine' then engine_text = 'PolyPerc' end
  screen.text_right(engine_text)
  screen.move(0,35)
  screen.text('cutoff: ' .. eng_cut)
  screen.move(0,45)
  screen.text('release: ' .. eng_rel)
  screen.move(0,55)
  screen.text('prob: ' .. tracks[current_track].pattern.prob)
  screen.move(120,55)
  screen.text_right('note: ' .. note_name)
  screen.update()
  screen_dirty = false
end

alt_func = false

engine_counter = 1

function key(n,z)
  if z == 1 and n == 1 then
    alt_func = true
  else 
    alt_func = false
  end
  if z == 1 and n == 2 then
    engine_counter = engine_counter + 1
    if engine_counter > TAB.count(engines) then engine_counter = 1 end
    if engines[engine_counter] == 'jf' then
      crow.ii.jf.mode(1)
    else
      crow.ii.jf.mode(0)
    end
    tracks[current_track].source = engines[engine_counter]
    redraw()
  end
end

function enc(n,d)
  if n == 1 then
    if not alt_func then
      local prev_length = tracks[current_track].pattern.length
      tracks[current_track].pattern.length = util.clamp(tracks[current_track].pattern.length + d*1,1,32)
      if tracks[current_track].pattern.length > prev_length then -- if the new length is longer, add some date/notes
        for i = 1, tracks[current_track].pattern.length do
          if tracks[current_track].pattern.gates[i] == nil then
            tracks[current_track].pattern.gates[i] = 0
            tracks[current_track].pattern.notes[i] = 60
            tracks[current_track].pattern.note_lengths[i] = eng_rel
          end
        end
      end
    else
      local prev_alt_length = tracks[current_track].pattern.offset_length
      tracks[current_track].pattern.offset_length = util.clamp(tracks[current_track].pattern.offset_length + d*1,1,8)
    end
    redraw()
  end
  if n == 2 then -- if encoder 3, then...
    if not alt_func then
      eng_cut = util.clamp(eng_cut + d*10,100,6000)
      -- crow_attack = util.clamp(crow_attack + d*0.01, 2, 0.1)
      redraw()
    else
      print('alt enc 2')
    end
  elseif n == 3 then
    if not alt_func then
      eng_rel = util.clamp(eng_rel + d*0.1,0.1,5)
      redraw()
    else
      tracks[current_track].pattern.prob = util.clamp(tracks[current_track].pattern.prob + d*5,0,100)
      redraw()
    end
  end
end





function grid.add(new_grid) -- must be grid.add, not g.add (this is a function of the grid class)
  print(new_grid.name.." says 'hello!'")
   -- each grid added can be queried for device information:
  print("new grid found at port: "..new_grid.port)
  g = grid.connect(new_grid.port) -- connect script to the new grid
  grid_connected = true -- a grid has been connected!
  grid_dirty = true -- enable flag to redraw grid, because data has changed
end

function grid.remove(g) -- must be grid.remove, not g.remove (this is a function of the grid class)
  print(g.name.." says 'goodbye!'")
end




-- UTILITY TO RESTART SCRIPT FROM MAIDEN
function r()
  norns.script.load(norns.state.script)
end
