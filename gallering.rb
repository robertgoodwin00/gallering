require 'wx'
require 'fastimage'

class ImageGalleryApp < Wx::App
  MAX_PER_PAGE = 12
  NUM_PAGINATION_LINKS = 20

  def on_init
    @frame = Wx::Frame.new(nil, title: 'Image Gallery', size: [1024, 768])
    @frame.set_max_size(Wx::Size.new(1024, 796))
    @main_sizer = Wx::BoxSizer.new(Wx::VERTICAL)

    @panel = Wx::Panel.new(@frame)
    @sizer = Wx::GridSizer.new(0, 4, 5, 5)
    @panel.set_sizer(@sizer)

    @main_sizer.add(@panel, 1, Wx::EXPAND | Wx::ALL, 5)

    @pagination_sizer = Wx::BoxSizer.new(Wx::HORIZONTAL)
    @search_sizer = Wx::BoxSizer.new(Wx::HORIZONTAL)
    @search_sizer.add(@pagination_sizer, 0, Wx::ALIGN_CENTER, 0)
    update_search_sizer
    @search_sizer.layout

    @main_sizer.add(@search_sizer, 0, Wx::ALIGN_CENTER | Wx::ALL, 5)

    @frame.set_sizer(@main_sizer)

    load_images
    load_image_tags
    @current_page = 0

    display_page

    @frame.center
    @frame.show

    evt_left_down(:on_click)
  end

  def update_search_sizer
    @random_tag_link = Wx::StaticText.new(@frame, label: "Random tag")
    @random_tag_link.set_foreground_colour(Wx::Colour.new("blue"))
    @random_tag_link.set_font(@random_tag_link.get_font.underlined)
    @search_sizer.add(@random_tag_link, 0, Wx::ALIGN_CENTER | Wx::LEFT, 10)

    @search_input = Wx::TextCtrl.new(@frame, style: Wx::TE_PROCESS_ENTER)
    @search_input.set_max_size(Wx::Size.new(300, -1))
    evt_text_enter(@search_input) do |evt|
      search_term = @search_input.value.strip.downcase
      perform_search(search_term)
    end
    @search_sizer.add(@search_input, 1, Wx::ALIGN_CENTER | Wx::LEFT | Wx::RIGHT, 5)

    @untagged_link = Wx::StaticText.new(@frame, label: "Untagged")
    @untagged_link.set_foreground_colour(Wx::Colour.new("blue"))
    @untagged_link.set_font(@untagged_link.get_font.underlined)
    @search_sizer.add(@untagged_link, 0, Wx::ALIGN_CENTER | Wx::RIGHT, 10)
    @search_sizer.layout
    @main_sizer.layout
  end

  def load_image_tags
    @image_tags = {}
    filename = 'tag_data.txt'
    if File.exist?(filename)
      File.readlines(filename).each do |line|
        match = line.strip.match(/^(.*?\.jpg|.*?\.jpeg)\s+(.*)/i)
        if match
          path = match[1]
          tags = match[2].split(' ')
          @image_tags[path] = tags
        end
      end
    end

    @images_path.each do |path|
      @image_tags[path] = [] unless @image_tags[path]
    end
  end

  def save_image_tags
    filename = 'tag_data.txt'
    File.open(filename, 'w') do |file|
      @image_tags.each do |path, tags|
        file.puts "#{path} #{tags.join(' ')}"
      end
    end
  end

  def load_images
    @images_path = Dir.glob("**/*.{jpg,jpeg}", File::FNM_CASEFOLD).select { |path| File.file?(path) }
    @total_pages = (@images_path.size.to_f / MAX_PER_PAGE).ceil
  end

  def apply_orientation(image, path)
    orientation = FastImage.new(path).orientation
    case orientation
    when 3 then image = image.rotate180
    when 6 then image = image.rotate90(true)
    when 8 then image = image.rotate90(false)
    end
    image
  end

  def display_page
    return if @current_page == @last_page && @images_path == @last_images

    @sizer.clear(true)

    start_index = @current_page * MAX_PER_PAGE
    end_index = [start_index + MAX_PER_PAGE - 1, @images_path.size - 1].min

    (start_index..end_index).each do |index|
      path = @images_path[index]
      next unless File.exist?(path)

      image = Wx::Image.new(path, Wx::BITMAP_TYPE_ANY)
      image = apply_orientation(image, path)

      max_width = 200
      max_height = 200
      ratio = [max_width.to_f / image.get_width, max_height.to_f / image.get_height].min
      scaled_width = (image.get_width * ratio).to_i
      scaled_height = (image.get_height * ratio).to_i
      image = image.scale(scaled_width, scaled_height)

      item_sizer = Wx::BoxSizer.new(Wx::VERTICAL)

      button = Wx::Button.new(@panel)
      button.set_bitmap(Wx::Bitmap.new(image))
      button.set_size(Wx::Size.new(scaled_width, scaled_height))
      button.set_client_data(index)
      evt_button(button, :on_button_click)
      item_sizer.add(button, 0, Wx::ALIGN_CENTER, 0)

      create_tags_and_edit_sizer(item_sizer, path)

      @sizer.add(item_sizer, 0, Wx::ALL, 5)
    end

    @sizer.layout
    update_pagination_sizer
  end

  def update_pagination_sizer
    @pagination_sizer.clear(true)

    first_link = Wx::StaticText.new(@frame, label: "<<", style: Wx::TE_RICH2)
    first_link.set_foreground_colour(@current_page > 0 ? Wx::Colour.new("blue") : Wx::Colour.new("grey"))
    first_link.set_font(first_link.get_font.underlined) if @current_page > 0
    first_link.set_client_data(0)
    @pagination_sizer.add(first_link, 0, Wx::LEFT | Wx::RIGHT, 10)

    prev_link = Wx::StaticText.new(@frame, label: "<", style: Wx::TE_RICH2)
    prev_link.set_foreground_colour(@current_page > 0 ? Wx::Colour.new("blue") : Wx::Colour.new("grey"))
    prev_link.set_font(prev_link.get_font.underlined) if @current_page > 0
    prev_link.set_client_data(@current_page - 1)
    @pagination_sizer.add(prev_link, 0, Wx::LEFT | Wx::RIGHT, 10)

    start_page = [@current_page - NUM_PAGINATION_LINKS / 2, 0].max
    end_page = [(start_page + NUM_PAGINATION_LINKS - 1), @total_pages - 1].min
    end_page = @total_pages - 1 if end_page - start_page < NUM_PAGINATION_LINKS - 1
    start_page = end_page - NUM_PAGINATION_LINKS + 1 if end_page - start_page < NUM_PAGINATION_LINKS - 1 && @total_pages > NUM_PAGINATION_LINKS

    (start_page..end_page).each do |page_num|
      link = Wx::StaticText.new(@frame, label: (page_num + 1).to_s, style: Wx::TE_RICH2)
      link.set_foreground_colour(Wx::Colour.new("blue")) if page_num != @current_page
      link.set_font(link.get_font.underlined) if page_num != @current_page
      link.set_client_data(page_num)
      @pagination_sizer.add(link, 0, Wx::LEFT | Wx::RIGHT, 10)
    end

    next_link = Wx::StaticText.new(@frame, label: ">", style: Wx::TE_RICH2)
    next_link.set_foreground_colour(@current_page < @total_pages - 1 ? Wx::Colour.new("blue") : Wx::Colour.new("grey"))
    next_link.set_font(next_link.get_font.underlined) if @current_page < @total_pages - 1
    next_link.set_client_data(@current_page + 1)
    @pagination_sizer.add(next_link, 0, Wx::LEFT | Wx::RIGHT, 10)

    last_link = Wx::StaticText.new(@frame, label: ">>", style: Wx::TE_RICH2)
    last_link.set_foreground_colour(@current_page < @total_pages - 1 ? Wx::Colour.new("blue") : Wx::Colour.new("grey"))
    last_link.set_font(last_link.get_font.underlined) if @current_page < @total_pages - 1
    last_link.set_client_data(@total_pages - 1)
    @pagination_sizer.add(last_link, 0, Wx::LEFT | Wx::RIGHT, 10)

    @pagination_sizer.layout
  end

  # ===== Helper: hide/show all pagination link widgets =====
  def set_pagination_visible(visible)
    @pagination_sizer.get_children.each do |item|
      win = item.get_window
      next unless win
      visible ? win.show : win.hide
    end
  end

  def on_click(event)
    clicked_object = event.get_event_object

    if clicked_object.is_a?(Wx::StaticText)
      client_data = clicked_object.get_client_data
      case client_data
      when Hash
        if client_data[:type] == 'edit'
          path = client_data[:path]
          item_sizer = clicked_object.get_containing_sizer

          tags_and_edit_sizer = clicked_object.get_containing_sizer
          item_sizer.detach(tags_and_edit_sizer)
          tags_and_edit_sizer.show_items(false)
          tags_and_edit_sizer.clear(true)

          text_input = Wx::TextCtrl.new(@panel, value: (@image_tags[path] || []).join(' '), style: Wx::TE_PROCESS_ENTER)

          evt_text_enter(text_input) do |evt|
            new_tags = text_input.value.split(' ')
            @image_tags[path] = new_tags
            save_image_tags
            item_sizer.detach(text_input)
            text_input.destroy
            create_tags_and_edit_sizer(item_sizer, path)
            item_sizer.layout
            display_page
          end

          evt_key_down(text_input) do |evt|
            if evt.get_key_code == Wx::K_ESCAPE
              item_sizer.detach(text_input)
              text_input.destroy
              create_tags_and_edit_sizer(item_sizer, path)
              item_sizer.layout
              display_page
            else
              evt.skip()
            end
          end

          item_sizer.add(text_input, 0, Wx::ALIGN_CENTER, 0)
          item_sizer.layout

          text_input.set_focus
          text_input.set_selection(-1, -1)
          text_input.set_size(Wx::Size.new(60, -1))

        elsif client_data[:type] == 'tag_search'
          on_tag_click(event)
        end
      when Integer
        @current_page = client_data
        display_page
      when nil
        if clicked_object == @random_tag_link
          on_random_tag_click(event)
        elsif clicked_object == @untagged_link
          on_untagged_click(event)
        end
      end

    elsif clicked_object.is_a?(Wx::Button)
      event.skip()

    elsif @full_view
      on_full_view_click(event)

    else
      event.skip()
    end
  end

  def create_tags_and_edit_sizer(item_sizer, path)
    tags_and_edit_sizer = Wx::BoxSizer.new(Wx::HORIZONTAL)

    if @image_tags[path]
      @image_tags[path].each do |tag|
        tag_label = Wx::StaticText.new(@panel, label: tag)
        tag_label.set_foreground_colour(Wx::Colour.new("blue"))
        tag_label.set_client_data({ type: 'tag_search', tag: tag })
        tags_and_edit_sizer.add(tag_label, 0, Wx::ALIGN_CENTER | Wx::RIGHT, 5)
      end
    end

    edit_link = Wx::StaticText.new(@panel, label: "EDIT")
    edit_link.set_foreground_colour(Wx::Colour.new("blue"))
    edit_link.set_font(edit_link.get_font.underlined)
    edit_link.set_client_data({ type: 'edit', path: path })
    tags_and_edit_sizer.add(edit_link, 0, Wx::ALIGN_CENTER, 0)

    item_sizer.add(tags_and_edit_sizer, 0, Wx::ALIGN_CENTER, 0)
  end

  # ===== Full view =====
  def on_button_click(event)
    button = event.get_event_object
    image_index = button.get_client_data
    image_path = @images_path[image_index]

    if @full_view
      on_full_view_click(event)
    else
      @full_view = true
      @frame.set_background_colour(Wx::Colour.new("black"))
      @frame.refresh

      # Hide all gallery UI: search controls, pagination, and image grid
      @search_input.hide
      @random_tag_link.hide
      @untagged_link.hide
      set_pagination_visible(false)
      @panel.hide

      @search_sizer.layout
      @main_sizer.layout

      full_image = Wx::Image.new(image_path, Wx::BITMAP_TYPE_ANY)
      full_image = apply_orientation(full_image, image_path)

      max_width = @frame.get_size.width
      max_height = @frame.get_size.height
      if full_image.get_width > full_image.get_height
        ratio = max_width.to_f / full_image.get_width
      else
        ratio = max_height.to_f / full_image.get_height
      end
      scaled_width = (full_image.get_width * ratio).to_i
      scaled_height = (full_image.get_height * ratio).to_i
      full_image = full_image.scale(scaled_width, scaled_height)

      full_bitmap = Wx::Bitmap.new(full_image)

      frame_width = @frame.get_size.width
      x_position = (frame_width - scaled_width) / 2

      @full_view_panel = Wx::Panel.new(@frame, style: Wx::SIMPLE_BORDER)
      size = Wx::Size.new(full_bitmap.get_width, full_bitmap.get_height)
      @full_view_panel.set_size(size)

      static_image = Wx::StaticBitmap.new(@full_view_panel, label: full_bitmap)

      @file_path_text = Wx::StaticText.new(@full_view_panel, label: image_path)
      @file_path_text.set_font(Wx::Font.new(12, Wx::FONTFAMILY_DEFAULT, Wx::FONTSTYLE_NORMAL, Wx::FONTWEIGHT_NORMAL))
      @file_path_text.set_foreground_colour(Wx::Colour.new("white"))
      @file_path_text.set_background_colour(Wx::Colour.new("black"))

      @full_view_panel.set_sizer(Wx::BoxSizer.new(Wx::VERTICAL))
      @full_view_panel.get_sizer.add(static_image, 1, Wx::ALIGN_CENTER | Wx::ALL, 5)
      @full_view_panel.get_sizer.add(@file_path_text, 0, Wx::ALIGN_CENTER | Wx::ALL, 5)
      @full_view_panel.get_sizer.set_min_size(frame_width, -1)

      @full_view_panel.show(true)
      @frame.layout

      @full_view_panel.set_position(Wx::Point.new(x_position, 0))
    end
  end

  def on_full_view_click(event)
    @full_view = false
    @frame.set_background_colour(Wx::Colour.new("white"))
    @frame.refresh

    if @full_view_panel
      @full_view_panel.destroy
      @full_view_panel = nil
    end

    # Re-show everything
    @panel.show
    @search_input.show
    @random_tag_link.show
    @untagged_link.show
    set_pagination_visible(true)

    @sizer.layout
    @search_sizer.layout
    @main_sizer.layout
  end

  def on_tag_click(event)
    clicked_object = event.get_event_object
    if clicked_object.is_a?(Wx::StaticText)
      client_data = clicked_object.get_client_data
      if client_data.is_a?(Hash) && client_data[:type] == 'tag_search'
        tag = client_data[:tag]
        @search_input.value = tag
        perform_search(tag)
      end
    end
  end

  def perform_search(search_term)
    if search_term.empty?
      load_images
    else
      search_tags = search_term.downcase.split(' ')

      @images_path = @image_tags.select do |_, tags|
        search_tags.all? do |search_tag|
          tags.any? { |tag| tag.downcase.include?(search_tag) }
        end
      end.keys

      @total_pages = (@images_path.size.to_f / MAX_PER_PAGE).ceil
    end

    @current_page = 0
    display_page
  end

  def on_random_tag_click(event)
    all_tags = @image_tags.values.flatten.uniq
    random_tag = all_tags.sample
    if random_tag
      @search_input.value = random_tag
      perform_search(random_tag)
    end
  end

  def on_untagged_click(event)
    @search_input.value = ""
    @images_path = @image_tags.select { |path, tags| (tags.nil? || tags.empty?) && path && File.exist?(path) }.keys
    @total_pages = (@images_path.size.to_f / MAX_PER_PAGE).ceil
    @current_page = 0
    display_page
  end
end

ImageGalleryApp.run

