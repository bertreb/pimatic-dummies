$(document).on 'templateinit', (event) ->

  # define the item class
  class LedLightItem extends pimatic.DeviceItem
    constructor: (templData, @device) ->
      super

      @id = templData.deviceId

      @power = null
      @brightness = null
      @color = null

    afterRender: (elements) ->
      super
      ### Apply UI elements ###

      @powerSlider = $(elements).find('.light-power')
      @powerSlider.flipswitch()
      $(elements).find('.ui-flipswitch').addClass('no-carousel-slide')

      @brightnessSlider = $(elements).find('.light-brightness')
      @brightnessSlider.slider()
      $(elements).find('.ui-slider').addClass('no-carousel-slide')

      @colorPicker = $(elements).find('.light-color')
      @colorPicker.spectrum
        preferredFormat: 'hex'
        showButtons: false
        allowEmpty: true
        move: (color) =>
          return @colorPicker.val(null).change() unless color
          @colorPicker.val("##{color.toHex()}").change()

      @colorPicker.on 'change', (e, payload) =>
        return if payload?.origin unless 'remote'
        @colorPicker.spectrum 'set', $(e.target).val()

      @_onLocalChange 'power', @_setPower
      @_onLocalChange 'brightness', @_setBrightness
      @_onLocalChange 'color', @_setColor

      ### React on remote user input ###

      @_onRemoteChange 'power', @powerSlider
      @_onRemoteChange 'brightness', @brightnessSlider
      @_onRemoteChange 'color', @colorPicker

      @colorPicker.spectrum('set', @color())
      @brightnessSlider.val(@brightness()).trigger 'change', [origin: 'remote']
      @powerSlider.val(@power()).trigger 'change', [origin: 'remote']


    _onLocalChange: (element, fn) ->
      timeout = 500 # ms

      # only execute one command at the time
      # delay the callback to protect the device against overflow
      queue = async.queue (arg, cb) =>
        fn.call(@, arg)
          .done( (data) ->
            ajaxShowToast(data)
            setTimeout cb, timeout
          )
          .fail( (data) ->
            ajaxAlertFail(data)
            setTimeout cb, timeout
          )
      , 1 # concurrency

      $('#index').on "change", "#item-lists ##{@id} .light-#{element}", (e, payload) =>
        return if payload?.origin is 'remote'
        return if @[element]?() is $(e.target).val()
        # flush queue to do not pile up commands
        # latest command has highest priority
        queue.kill() if queue.length() > 2
        queue.push $(e.target).val()

    _onRemoteChange: (attributeString, el) ->
      attribute = @getAttribute(attributeString)

      unless attributeString?
        throw new Error("A LED-Light device needs an #{attributeString} attribute!")

      @[attributeString] = ko.observable attribute.value()
      attribute.value.subscribe (newValue) =>
        @[attributeString] newValue
        el.val(@[attributeString]()).trigger 'change', [origin: 'remote']

    _setPower: (state) ->
      if state is 'on'
        @device.rest.turnOn {}, global: no
      else
        @device.rest.turnOff {}, global: no

    _setColor: (colorCode) ->
      unless colorCode
        @device.rest.setWhite {}, global: no
      else
        @device.rest.setColor {colorCode: colorCode},  global: no

    _setBrightness: (brightnessValue) ->
      @device.rest.setBrightness {brightnessValue: brightnessValue}, global: no

  class LightDimmerItem extends pimatic.SwitchItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @dsliderId = "dimmer-#{templData.deviceId}"
      dimAttribute = @getAttribute('dimlevel')
      dimlevel = dimAttribute.value
      @dsliderValue = ko.observable(if dimlevel()? then dimlevel() else 0)
      dimAttribute.value.subscribe( (newDimlevel) =>
        @dsliderValue(newDimlevel)
        pimatic.try => @dsliderEle.slider('refresh')
      )

    getItemTemplate: => 'light-dimmer'

    onSliderStop: ->
      @dsliderEle.slider('disable')
      @device.rest.changeDimlevelTo( {dimlevel: @dsliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @dsliderEle.val(@getAttribute('dimlevel').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @dsliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

    afterRender: (elements) ->
      super(elements)
      @updateClass()
      @dsliderEle = $(elements).find('#' + @dsliderId)
      @dsliderEle.slider()
      $(elements).find('.ui-slider').addClass('no-carousel-slide')
      $('#index').on("slidestop", " #item-lists #"+@dsliderId , (event) ->
          ddev = ko.dataFor(this)
          ddev.onSliderStop()
          return
      )

    updateClass: ->
      return
      value = @getAttribute('presence').value()
      if @presenceEle?
        switch value
          when true
            @presenceEle.addClass('value-present')
            @presenceEle.removeClass('value-absent')
          when false
            @presenceEle.removeClass('value-present')
            @presenceEle.addClass('value-absent')
          else
            @presenceEle.removeClass('value-absent')
            @presenceEle.removeClass('value-present')
        return

##############################################################
# based on RaspBeeRGBCTItem
##############################################################
  class LightRGBCTItem extends LightDimmerItem

    constructor: (templData, @device) ->
      super(templData, @device)
      @_colorChanged = false
      @csliderId = "color-#{templData.deviceId}"
      colorAttribute = @getAttribute('ct')
      unless colorAttribute?
        throw new Error("A dimmer device needs an ct attribute!")
      color = colorAttribute.value
      @csliderValue = ko.observable(if color()? then color() else 0)
      colorAttribute.value.subscribe( (newColor) =>
        @csliderValue(newColor)
        pimatic.try => @csliderEle.slider('refresh')
      )
      @pickId = "pick-#{templData.deviceId}"

    getItemTemplate: => 'light-rgbct'

    onSliderStop2: ->
      @csliderEle.slider('disable')
      @device.rest.setCT( {colorCode: @csliderValue()}, global: no).done(ajaxShowToast)
      .fail( =>
        pimatic.try => @csliderEle.val(@getAttribute('ct').value()).slider('refresh')
      ).always( =>
        pimatic.try( => @csliderEle.slider('enable'))
      ).fail(ajaxAlertFail)

    afterRender: (elements) ->
      @csliderEle = $(elements).find('#' + @csliderId)
      @csliderEle.slider()
      super(elements)
      $('#index').on("slidestop", " #item-lists #"+@csliderId, (event) ->
          cddev = ko.dataFor(this)
          cddev.onSliderStop2()
          return
      )
      $(elements).on("dragstop.spectrum","#"+@pickId, (color) =>
          @_changeColor(color)
      )
      @colorPicker = $(elements).find('.light-color')
      @colorPicker.spectrum
        preferredFormat: 'hex'
        showButtons: false
        allowEmpty: true
        showInput: true

      $('.sp-container').addClass('ui-corner-all ui-shadow')

      @colorPicker.on 'change', (e, payload) =>
        return if payload?.origin unless 'remote'
        @colorPicker.spectrum 'set', $(e.target).val()
      @_onRemoteChange 'color', @colorPicker

    _onRemoteChange: (attributeString, el) ->
      attribute = @getAttribute(attributeString)
      unless attributeString?
        throw new Error("An RGBCT-Light device needs an #{attributeString} attribute!")

      @[attributeString] = ko.observable attribute.value()
      attribute.value.subscribe (newValue) =>
        @[attributeString] newValue
        el.val(@[attributeString]()).trigger 'change', [origin: 'remote']

    _changeColor: (color) ->
      color = @colorPicker.spectrum('get').toHex()
      return @device.rest.setColor(
          {colorCode: color}, global: no
        ).then(ajaxShowToast, ajaxAlertFail)

  # register the item-class
  pimatic.templateClasses['led-light'] = LedLightItem
  pimatic.templateClasses['light-rgbct'] = LightRGBCTItem