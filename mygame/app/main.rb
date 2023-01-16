module Color
  ARRAY = {
    blue: [12, 27, 51],
    khaki: [178, 170, 142],
    purple: [122, 48, 108],
    red: [219, 90, 66],
    light_blue: [25, 133, 161],
    hacker_green: [32, 194, 14],
    coal: [21, 27, 31]
  }

  HASH = ARRAY.map do |color, (r, g, b)|
    [color, {r: r, g: g, b: b}]
  end.to_h
end


class Game
  attr_gtk

  DEFAULT_DIFFICULTY = 14

  def label(msg, x: 1280/2, y: 720 - 30,
            r: Color::HASH[:khaki][:r], g: Color::HASH[:khaki][:g], b: Color::HASH[:khaki][:b],
            a: 255,
            font: "fonts/ocrae.ttf",
            size_enum: 1,
            alignment_enum: 1,
            size: nil)
    {
      x: x, y: y,
      text: msg,
      r: r, g: g, b: b,
      size_enum: size || size_enum,
      alignment_enum: alignment_enum,
      a: a,
      font: font
    }

  end

  def tick_count()= args.tick_count

  def bad_signal?
    state.signal_counts.values.any? {|val| val > 1}
  end

  def tick
    if keyboard.key_down.escape
      return $gtk.reset
    end

    setup!

    if state.game_state == :game_over

      outputs.labels << label("Somebody set up us the bomb.", x: 1280/2, y: 720/2, **Color::HASH[:red])
      outputs.labels << label("Type duplicate keys to unscramble signal.", x: 1280/2, y: 200)
      outputs.labels << label("For great justice.", x: 1280/2, y: 200 - 30)
      outputs.labels << label("[esc]", x: 1280/2, y: 100, **Color::HASH[:red])
      return
    end

    listen_for_signal!
    actuate_signals!
    render_signals!


    if bad_signal?
      state.bad_signal_for += 1

      outputs.solids << [0, 10, 1280 * (state.bad_signal_for / 3.seconds), 40, *Color::ARRAY[:red]]
      if state.bad_signal_for > 3.seconds
        state.game_state = :game_over

        args.state.audio_playtime_transition_to = args.audio[:bg].playtime

        args.audio[:bg] = {
          input: "sounds/main-grey.wav",
          looping: true
        }

        return
      end
    else
      state.bad_signal_for = 0
    end

    if inputs.keyboard.keys[:down].any?
      keys = inputs.keyboard.keys[:down]
      explode_index = nil

      state.signals.each.with_index do |signal, i|
        if keys.delete(signal.signal) && state.signal_counts[signal.signal] > 1
          break explode_index = i
        end
      end

      if explode_index
        state.signals[0..explode_index].each(&:explode!)
        state.bad_signal_for = 0
      end

      # if leftover keys, you pressed something you shouldn't have
      if keys.any?
        state.bad_signal_for += 10
      end
    end

    outputs.labels << label("[esc] to reset", x: 1280 - 10, y: 700, alignment_enum: 2, **Color::HASH[:purple])

    outputs.labels << label("Signals Observed: #{state.signals_seen}", size: 6, **Color::HASH[:red])

    if winning?
      outputs.labels << label("MAIN SCREEN TURN ON!", y: 200, size_enum: 20)
    end

  end

  def winning?
    state.signals.size == state.difficulty && !bad_signal?
  end

  def listen_for_signal!
    return unless should_send_signal?
    new_signal = Signal.new(state.input.shift)
    state.signals << new_signal
    state.signal_counts[new_signal.signal] += 1

    state.last_signal_at = tick_count
    state.signals_seen += 1
  end

  def actuate_signals!
    last_signal_border = 130
    $args.state
    state.signals.each.with_index do |signal, i|

      next_x = signal.x - 30

      signal.x = [next_x, last_signal_border].max
      last_signal_border = (signal.x + signal.width)
    end
  end

  def should_send_signal?
    state.input.any? && state.signals.count < state.difficulty && state.last_signal_at.elapsed?(0.3.seconds)
  end

  def render_signals!
    outputs.labels << state.signals.map do |signal|
      label(
        signal.signal.to_s.upcase,
        x: signal.x,
        y: signal.y,
        size: signal.size_enum,
        alignment_enum: signal.alignment_enum,
        font: signal.font,
        **Color::HASH[:hacker_green]
      )
    end
    state.signals.each(&:render)
  end

  def setup!
    init if tick_count == 0
    outputs.background_color = Color::ARRAY[:blue]
    if time = state.audio_playtime_transition_to
      args.audio[:bg].playtime = time
      state.audio_playtime_transition_to = nil
    end
  end

  def init
    state.input = $gtk.read_file("data/input.txt").chars.map(&:to_sym)
    # state.input = "nznrnfrfntjfmvfwmzdfjlvtqnbhcprsg".chars.map(&:to_sym)
    state.signals_seen = 0
    state.difficulty = DEFAULT_DIFFICULTY
    state.signals = []
    state.signals_seen = 0
    state.last_signal_at = 0
    state.signal_counts = Hash.new(0)
    state.bad_signal_for = 0
    state.game_state = :playing
    args.audio[:bg] = {
      input: "sounds/main.wav",
      looping: true
    }
    args.state.audio_playtime_transition_to = nil
  end
end

class Signal
  attr_sprite

  attr_reader :signal

  SPEED = 20

  def initialize(signal, x: 1280, y: 450)
    @signal = signal
    @x = x
    @y = y

    @last_visual_y = 100
    @last_visual_x = x
    @last_visual_w = 10
    @last_visual_h = 500
  end

  def size_enum
    50
  end

  def font
    "fonts/ocrae.ttf"
  end

  def text
    signal
  end

  def width
    $gtk.args.gtk.calcstringbox(signal.to_s, size_enum, font)[0]
  end

  def height
    $gtk.args.gtk.calcstringbox(signal.to_s, size_enum, font)[1]
  end

  def alignment_enum
    0
  end

  def explode!
    $gtk.args.state.signal_counts[signal] -=1
    $gtk.args.state.signals.delete(self)
  end

  def outputs
    $gtk.args.outputs
  end

  def render


    next_visual_y = @last_visual_y
    next_visual_x = @last_visual_x
    next_visual_w = @last_visual_w
    next_visual_h = @last_visual_h
    color = @last_color || Color::ARRAY[:hacker_green]

      if $gtk.args.state.signal_counts.values.all? {|val| val < 2}
        next_visual_y = (@last_visual_y + rand(7) - 3).clamp(0, 720)
        next_visual_x = (x + width / 2 + (rand(3) - 1)).clamp(x, x + width)
        next_visual_w = @last_visual_w
        next_visual_h = 300
        color = Color::ARRAY[:purple]
      else
        next_visual_y = (@last_visual_y + rand(200) - 100).clamp(0, 720 - 300)
        next_visual_x = (x + width / 2 + (rand(20) - 10)).clamp(x, x + width)
        next_visual_w = (@last_visual_w + (rand(3) - 1)).clamp(1, width)
        next_visual_h = 300 + (rand(50) - 20)
        color = Color::ARRAY[:light_blue].map{|color| color + (rand(50) - 20)}
      end

    $gtk.args.outputs.solids << [next_visual_x,
                                next_visual_y,
                                next_visual_w,
                                next_visual_h,
                                *color,
                                100
                              ]
    outputs.solids << [x, y, width, -1 * height, *Color::ARRAY[:coal]]


    @last_visual_y = next_visual_y
    @last_visual_x = next_visual_x
    @last_visual_w = next_visual_w
    @last_visual_h = next_visual_h
    @last_color = color
  end

end


$game = Game.new

def tick args
  $game.args = args
  $game.tick
end


  # module AttrGTK
  #   attr_accessor :args
  
  #   def keyboard
  #     args.inputs.keyboard
  #   end
  
  #   def grid
  #     args.grid
  #   end
  
  #   def state
  #     args.state
  #   end
  
  #   def temp_state
  #     args.temp_state
  #   end
  
  #   def inputs
  #     args.inputs
  #   end
  
  #   def outputs
  #     args.outputs
  #   end
  
  #   def gtk
  #     args.gtk
  #   end
  
  #   def passes
  #     args.passes
  #   end
  
  #   def pixel_arrays
  #     args.pixel_arrays
  #   end
  
  #   def geometry
  #     args.geometry
  #   end
  
  #   def layout
  #     args.layout
  #   end
  
  #   def events
  #     args.events
  #   end
  
  #   def new_entity entity_type, init_hash = nil, &block
  #     args.state.new_entity entity_type, init_hash, &block
  #   end
  
  #   def new_entity_strict entity_type, init_hash = nil, &block
  #     args.state.new_entity_strict entity_type, init_hash, &block
  #   end
  # end