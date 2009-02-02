#Copyright (c) 2009, Unintelligible
#All rights reserved.
#
#Redistribution and use in source and binary forms, with or without 
#modification, are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright notice, 
#      this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright 
#      notice, this list of conditions and the following disclaimer in the 
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the Unintelligible nor the names of its contributors
#      may be used to endorse or promote products derived from this software 
#      without specific prior written permission.
#
#SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
#ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE 
#FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
#DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
#SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
#CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, 
#OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
#USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#TODO
#* use pixelgrabber to get pixels in fitness function (maybe faster than iterating?)
#* improve use of randomness to ensure a new candidate is generated for each run - this
#  should improve performance
#* third image to display the current candidate between the Before and After images
#* button to start/pause the generation
#* more detailed timing stats (specifically, for the fitness test)
#* threading

require 'java'

module Swing
    include_package 'javax.swing'
    include_package 'javax.swing.event'
end

module Awt
    include_package 'java.awt'
    include_package 'java.awt.event'
    include_package 'java.awt.image'
end

include_class 'javax.imageio.ImageIO'
include_class('java.io.File') {|p,n| "JFile" }

class MainWindow < Swing::JFrame
    def initialize
        super "Mona Lisa"
        setDefaultCloseOperation Swing::JFrame::EXIT_ON_CLOSE
        image_file = ARGV.length > 0 ? ARGV[0] : "ml.jpg"
        @save_dumps = ARGV.length > 1 && ARGV[1] == "savedumps"
        image = ImageIO.read(JFile.new(image_file)) #returns a buffered image
        @@max_width, @@max_height = image.get_width, image.get_height
        main_panel = Swing::JPanel.new(Awt::GridLayout.new(3,2))

        before_panel = MyPanel.new
        before_panel.image = image
        after_panel = MyPanel.new
        main_panel.add(before_panel)
        main_panel.add(after_panel)
        main_panel.add(Swing::JLabel.new("Before"))
        main_panel.add(Swing::JLabel.new("After"))
        main_panel.add(Swing::JLabel.new(""))
        iterations_label = Swing::JTextArea.new()
        iterations_label.editable = false
        iterations_label.background = before_panel.background
        main_panel.add(iterations_label)
        add(main_panel)

        @runs, @generation, @selected, @start_time = 0, 0, 0, java.lang.System.current_time_millis
        timer = Swing::Timer.new(500, nil)
        timer.add_action_listener { |action_event|
            run_seconds = (java.lang.System.current_time_millis - @start_time) / 1000
            rps = (@runs.to_f / run_seconds.to_f)
            iterations_label.text = "#{@runs} runs, #{@generation} generations, #{@selected} fittest selected \nrunning for #{run_seconds} seconds\n(#{rps} runs per second)"
        }
        timer.start

        current_drawing = DnaDrawing.new.init
        current_error_level = java.lang.Long::MAX_VALUE
        #black image to start with
        new_image = Awt::BufferedImage.new(@@max_width, @@max_height, Awt::BufferedImage::TYPE_INT_ARGB)
        new_graphics = new_image.get_graphics
        new_graphics.set_color(Awt::Color::BLACK)
        new_graphics.fill_rect(0,0,@@max_width,@@max_height)
        Thread.new do |t|
            after_panel.image = new_image
            after_panel.repaint
            fitness = FitnessCalculator.new(image)
            while(true) #Ctlr-C to quit
                new_drawing = current_drawing.dup
                new_drawing.mutate
                @runs += 1
                if(new_drawing.dirty)
                    @generation += 1
                    new_image = Awt::BufferedImage.new(@@max_width, @@max_height, Awt::BufferedImage::TYPE_INT_ARGB)
                    new_graphics = new_image.get_graphics
                    new_graphics.set_color(Awt::Color::BLACK)
                    new_graphics.fill_rect(0,0,@@max_width,@@max_height)
                    new_drawing.polygons.each do |poly|
                        new_graphics.set_color(poly.dna_color.to_awt_color)
                        new_graphics.fill_polygon(poly.to_awt_polygon)
                    end
                    new_error_level = fitness.calculate(new_image)
                    puts "calculated fitness - new error level #{new_error_level}, old error level #{current_error_level}"
                    if(new_error_level < current_error_level)
                        @selected += 1
                        puts "new fitter image, redrawing"
                        after_panel.image = new_image
                        after_panel.repaint
                        current_drawing = new_drawing
                        current_error_level = new_error_level
                        if @save_dumps
                            puts "saving image" 
                            ImageIO.write(new_image, "png", JFile.new("dumps/dump-#{@generation.to_s.rjust(9,'0')}.png")) 
                        end
                    end
                end
            end
        end
    end
end

class MyPanel < Swing::JPanel
    def image=(image)
        @img = image
    end

    def paint(g)
        super g
        g.fill_rect(0, 0,  @img.get_width, @img.get_height)
        g.draw_image(@img, nil, 0, 0)
    end
end

def draw_polygon(graphics, polygon, color)
    graphics.set_color(color)
    graphics.fill_polygon(polygon)
end

def mutate?(mutation_rate)
    rand(mutation_rate.abs) == 1
end

@@max_width = 0
@@max_height = 0

@@active_add_point_mutation_rate = 1500
@@active_add_polygon_mutation_rate = 700
@@active_alpha_mutation_rate = 1500
@@active_alpha_range_max = 255 #was 60
@@active_alpha_range_min = 1 #was 30
@@active_blue_mutation_rate = 1500
@@active_blue_range_max = 255
@@active_blue_range_min = 0
@@active_green_mutation_rate = 1500
@@active_green_range_max = 255
@@active_green_range_min = 0
@@active_move_point_max_mutation_rate = 1500
@@active_move_point_mid_mutation_rate = 1500
@@active_move_point_min_mutation_rate = 1500
@@active_move_point_range_mid = 20
@@active_move_point_range_min = 3
@@active_move_polygon_mutation_rate = 700
@@active_points_max = 1500
@@active_points_min = 0
@@active_points_per_polygon_max = 10
@@active_points_per_polygon_min = 3
@@active_polygons_max = 255
@@active_polygons_min = 0
@@active_red_mutation_rate = 1500
@@active_red_range_max = 255
@@active_red_range_min = 0
@@active_remove_point_mutation_rate = 1500
@@active_remove_polygon_mutation_rate = 1500
@@add_point_mutation_rate = 1500
#_mutation rates
@@add_polygon_mutation_rate = 700
@@alpha_mutation_rate = 1500
@@alpha_range_max = 60
@@alpha_range_min = 30
@@blue_mutation_rate = 1500
@@blue_range_max = 255
@@blue_range_min = 0
@@green_mutation_rate = 1500
@@green_range_max = 255
@@green_range_min = 0
@@move_point_max_mutation_rate = 1500
@@move_point_mid_mutation_rate = 1500
@@move_point_min_mutation_rate = 1500
@@move_point_range_mid = 20
@@move_point_range_min = 3
@@move_polygon_mutation_rate = 700
@@points_max = 1500
@@points_min = 0
@@points_per_polygon_max = 10
@@points_per_polygon_min = 3
@@polygons_max = 255
@@polygons_min = 0
@@red_mutation_rate = 1500
@@red_range_max = 255
@@red_range_min = 0
@@remove_point_mutation_rate = 1500
@@remove_polygon_mutation_rate = 1500

class DnaDrawing
    attr_accessor :polygons, :dirty
    def initialize
        @polygons = Array.new
        @dirty = false
    end

    def point_count
        @polygons.inject(0){|sum, p| sum + p.points.length }
    end

    def init
        @@active_polygons_min.times{ add_polygon }
        @dirty = true
        self
    end

    def dup
        d = DnaDrawing.new
        @polygons.each{|p| d.polygons << p.dup }
        d
    end
    
    def mutate
        add_polygon if mutate?(@@active_add_polygon_mutation_rate)
        remove_polygon if mutate?(@@active_remove_polygon_mutation_rate)
        move_polygon if mutate?(@@active_move_polygon_mutation_rate)
        @polygons.each{|p| p.mutate(self)}
    end

    def move_polygon
        return if @polygons.length == 0
        poly = @polygons.delete_at(rand(@polygons.length))
        @polygons.insert(rand(@polygons.length), poly)
        @dirty = true
    end

    def remove_polygon
        if(@polygons.length > @@active_polygons_min)
            @polygons.delete_at(rand(@polygons.length))
            @dirty = true
        end
    end

    def add_polygon
        if(@polygons.length < @@active_polygons_max)
            @polygons.insert(rand(@polygons.length), DnaPolygon.new.init)
            @dirty = true
        end
    end
end

class DnaPolygon
    attr_accessor :points, :dna_color

    def initialize
        @points = Array.new
    end

    def init
        origin = DnaPoint.new.init
        @@active_points_per_polygon_min.times do |i|
            p = DnaPoint.new
            p.X = [ [0, origin.X + (rand(6) - 3)].max, @@max_width].min
            p.Y = [ [0, origin.Y + (rand(6) - 3)].max, @@max_height].min
            @points << p
        end

        @dna_color = DnaColor.new.init
        self
    end

    def dup
        p = DnaPolygon.new
        p.dna_color = @dna_color.dup
        @points.each{|pnt| p.points << pnt.dup }
        p
    end

    def mutate(dna_drawing)
        add_point(dna_drawing) if mutate?(@@active_add_point_mutation_rate)
        remove_point(dna_drawing) if mutate?(@@active_remove_point_mutation_rate)
        @dna_color.mutate(dna_drawing)
        @points.each{|p| p.mutate(dna_drawing) }
    end

    def remove_point(dna_drawing)
        if( @points.length > @@active_points_per_polygon_min && dna_drawing.point_count > @@active_points_min)
            @points.delete_at(rand(@points.length))
            dna_drawing.dirty = true
        end
    end

    def add_point(dna_drawing)
        if( @points.length < @@active_points_per_polygon_max && dna_drawing.point_count < @@active_points_max)
            idx = rand(@points.length - 1) + 1
            pnt_prev = @points[idx - 1]
            pnt_next = @points[idx]
            point = DnaPoint.new
            point.X = (pnt_prev.X + pnt_next.X) / 2
            point.Y = (pnt_prev.Y + pnt_next.Y) / 2

            @points.insert(idx, point)
            dna_drawing.dirty = true
        end
    end

    def to_awt_polygon
        awtpoly = Awt::Polygon.new
        @points.each{|pnt| awtpoly.add_point(pnt.X, pnt.Y)}
        awtpoly
    end

end

class DnaColor
    attr_accessor :red, :green, :blue, :alpha

    def init
        @red = rand(255)
        @green = rand(255)
        @blue = rand(255)
        @alpha = rand(255)
        self
    end

    def dup
        b = DnaColor.new
        b.red, b.green, b.blue, b.alpha = @red, @green, @blue, @alpha
        b
    end

    def mutate(dna_drawing)
        if(mutate?(@@active_red_mutation_rate))
            @red = rand(@@active_red_range_max - @@active_red_range_min) + @@active_red_range_min
            dna_drawing.dirty = true
        end
        if(mutate?(@@active_green_mutation_rate))
            @green = rand(@@active_green_range_max - @@active_green_range_min) + @@active_green_range_min
            dna_drawing.dirty = true
        end
        if(mutate?(@@active_blue_mutation_rate))
            @blue = rand(@@active_blue_range_max - @@active_blue_range_min) + @@active_blue_range_min
            dna_drawing.dirty = true
        end
        if(mutate?(@@active_alpha_mutation_rate))
            @alpha = rand(@@active_alpha_range_max - @@active_alpha_range_min) + @@active_alpha_range_min
            dna_drawing.dirty = true
        end
    end

    def to_awt_color
        Awt::Color.new(@red.to_f / 255, @green.to_f / 255, @blue.to_f / 255, @alpha.to_f / 255)
    end
end

class DnaPoint
    attr_accessor :X, :Y

    def init
        @X, @Y = rand(@@max_width), rand(@@max_height)
        self
    end

    def dup
        p = DnaPoint.new
        p.X, p.Y = @X, @Y
        p
    end

    def mutate(dna_drawing)
        if(mutate?(@@active_move_point_max_mutation_rate))
            @X, @Y = rand(@@max_width), rand(@@max_height)
            dna_drawing.dirty = true
        end

        if(mutate?(@@active_move_point_mid_mutation_rate))
            @X = [ [0, @X + rand(@@active_move_point_range_mid) - @@active_move_point_range_mid].max, @@max_width].min
            @Y = [ [0, @Y + rand(@@active_move_point_range_mid) - @@active_move_point_range_mid].max, @@max_height ].min
            dna_drawing.dirty = true
        end

        if(mutate?(@@active_move_point_min_mutation_rate))
            @X = [ [0, @X + rand(@@active_move_point_range_min) - @@active_move_point_range_min].max, @@max_width ].min
            @Y = [ [0, @Y + rand(@@active_move_point_range_min) - @@active_move_point_range_min, @@max_height].max, @@max_height].min
            dna_drawing.dirty = true
        end
    end
end


class FitnessCalculator
    def initialize(source_image)
       @source_pixels = grab_pixels(source_image)
    end

    def grab_pixels(buffered_image)
#        pixels = Array.new(buffered_image.get_width * buffered_image.get_height, 0)
#        puts "about to grab pixels"
#        pg = Awt::PixelGrabber.new(buffered_image, 0, 0, buffered_image.get_width,
#                buffered_image.get_height, pixels.to_java(:int), 0, buffered_image.get_width)
#        puts "initialized pixel grabber"
#        pg.grab_pixels
#        puts "finished grabbing pixels"
#        pixels
        pixels = Array.new(buffered_image.get_width)
        buffered_image.get_width.times do |x|
            pixels[x] = Array.new(buffered_image.get_height)
            buffered_image.get_height.times do |y|
                rgb = buffered_image.get_rgb(x,y)
                pixels[x][y] = rgb
            end
        end
        pixels
    end

    def calculate(new_image)
        dest_pixels = grab_pixels(new_image)
        acc = 0
        @source_pixels.length.times do |source_x|
            @source_pixels[source_x].length.times do |source_y|
                source_pixel = @source_pixels[source_x][source_y];
                dest_pixel = dest_pixels[source_x][source_y];
                r = ((source_pixel >> 16) & 0xFF) - ((dest_pixel >> 16) & 0xFF);
                g = ((source_pixel >> 8) & 0xFF) - ((dest_pixel >> 8) & 0xFF);
                b = (source_pixel & 0xFF) - (dest_pixel & 0xFF);
                acc += r * r + g * g + b * b
            end
        end
        acc
    end
end

main_window = MainWindow.new
main_window.setVisible(true)

