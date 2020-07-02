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
      @colorPicker.spectrum 'set', @color()

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

  class DummyThermostatItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)

      # The value in the input
      @inputValue = ko.observable()
      @inputValue2 = ko.observable()
      @inputValue3 = ko.observable()

      # temperatureSetpoint changes -> update input + also update buttons if needed
      @stAttr = @getAttribute('temperatureSetpoint')
      @stAttr2 = @getAttribute('temperatureSetpointLow')
      @stAttr3 = @getAttribute('temperatureSetpointHigh')
      @inputValue(@stAttr.value())
      @inputValue2(@stAttr2.value())
      @inputValue3(@stAttr3.value())

      attrValue = @stAttr.value()
      @stAttr.value.subscribe( (value) =>
        @inputValue(value)
        attrValue = value
      )

      attrValue2 = @stAttr2.value()
      @stAttr2.value.subscribe( (value) =>
        @inputValue2(value)
        attrValue2 = value
      )

      attrValue3 = @stAttr3.value()
      @stAttr3.value.subscribe( (value) =>
        @inputValue3(value)
        attrValue3 = value
      )

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue = @inputValue()
        if textValue? and attrValue? and parseFloat(attrValue) isnt parseFloat(textValue)
          @changeTemperatureTo(parseFloat(textValue))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue2 = @inputValue2()
        if textValue2? and attrValue2? and parseFloat(attrValue2) isnt parseFloat(textValue2)
          @changeTemperatureLowTo(parseFloat(textValue2))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue3 = @inputValue3()
        if textValue3? and attrValue3? and parseFloat(attrValue3) isnt parseFloat(textValue3)
          @changeTemperatureHighTo(parseFloat(textValue3))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      @synced = @getAttribute('synced').value

    getItemTemplate: => 'dummythermostat'

    afterRender: (elements) =>
      super(elements)

      # find the buttons
      @heatButton = $(elements).find('[name=heatButton]')
      @heatcoolButton = $(elements).find('[name=heatcoolButton]')
      @coolButton = $(elements).find('[name=coolButton]')
      @offButton = $(elements).find('[name=offButton]')
      @ecoButton = $(elements).find('[name=ecoButton]')
      @onButton = $(elements).find('[name=onButton]')
      @manualButton = $(elements).find('[name=manualButton]')
      @autoButton = $(elements).find('[name=autoButton]')
      @input = $(elements).find('[name=spin]')
      @input.spinbox()
      @input2 = $(elements).find('[name=spin2]')
      @input2.spinbox()
      @input3 = $(elements).find('[name=spin3]')
      @input3.spinbox()

      @updatePowerButtons()
      @updateEcoButton()
      @updateModeButtons()
      @updateProgramButtons()
      #@updatePreTemperature()

      @getAttribute('mode')?.value.subscribe( => @updateModeButtons() )
      @getAttribute('power')?.value.subscribe( => @updatePowerButtons() )
      @getAttribute('program')?.value.subscribe( => @updateProgramButtons() )
      @getAttribute('eco')?.value.subscribe( => @updateEcoButton() )
      #@stAttr.value.subscribe( => @updatePreTemperature() )
      #@stAttrLow.value.subscribe( => @updatePreTemperature() )
      #@stAttrHigh.value.subscribe( => @updatePreTemperature() )
      return

    # define the available actions for the template
    modeHeat: -> @changeModeTo "heat"
    modeHeatCool: -> @changeModeTo "heatcool"
    modeCool: -> @changeModeTo "cool"
    modeOff: -> @changePowerTo false
    #modeEco: -> @changePowerTo "eco"
    modeEcoToggle: -> @toggleEco ""
    modeOn: -> @changePowerTo true
    modeManual: -> @changeProgramTo "manual"
    modeAuto: -> @changeProgramTo "auto"
    setTemp: -> @changeTemperatureTo "#{@inputValue.value()}"
    setTempLow: -> @changeTemperatureLowTo "#{@inputValue2.value()}"
    setTempHigh: -> @changeTemperatureHighTo "#{@inputValue3.value()}"

    updateModeButtons: =>
      modeAttr = @getAttribute('mode')?.value()
      switch modeAttr
        when 'heat'
          @heatButton.addClass('ui-btn-active')
          @heatcoolButton.removeClass('ui-btn-active')
          @coolButton.removeClass('ui-btn-active')
          @input.spinbox('enable')
          @input2.spinbox('disable')
          @input3.spinbox('disable')
        when 'heatcool'
          @heatButton.removeClass('ui-btn-active')
          @heatcoolButton.addClass('ui-btn-active')
          @coolButton.removeClass('ui-btn-active')
          @input.spinbox('disable')
          @input2.spinbox('enable')
          @input3.spinbox('enable')
        when 'cool'
          @heatButton.removeClass('ui-btn-active')
          @heatcoolButton.removeClass('ui-btn-active')
          @coolButton.addClass('ui-btn-active')
          @input.spinbox('enable')
          @input2.spinbox('disable')
          @input3.spinbox('disable')
      return

    updateEcoButton: =>
      ecoAttr = @getAttribute('eco')?.value()
      if ecoAttr is true
        @ecoButton.addClass('ui-btn-active')
      else
        @ecoButton.removeClass('ui-btn-active')
      return

    updateProgramButtons: =>
      programAttr = @getAttribute('program')?.value()
      switch programAttr
        when 'manual'
          @manualButton.addClass('ui-btn-active')
          @autoButton.removeClass('ui-btn-active')
        when 'auto'
          @manualButton.removeClass('ui-btn-active')
          @autoButton.addClass('ui-btn-active')
      return

    updatePowerButtons: =>
      powerAttr = @getAttribute('power')?.value()
      if powerAttr is false
        @offButton.addClass('ui-btn-active')
        @onButton.removeClass('ui-btn-active')
      else
        @offButton.removeClass('ui-btn-active')
        @onButton.addClass('ui-btn-active')
      return

    updatePreTemperature: ->
      return
      if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.ecoTemp}")
        @boostButton.removeClass('ui-btn-active')
        @comfyButton.removeClass('ui-btn-active')
      else if parseFloat(@stAttr.value()) is parseFloat("#{@device.config.comfyTemp}")
        @boostButton.removeClass('ui-btn-active')
        @comfyButton.addClass('ui-btn-active')
      else
        @comfyButton.removeClass('ui-btn-active')
      return

    changeModeTo: (mode) ->
      @device.rest.changeModeTo({mode}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changePowerTo: (power) ->
      @device.rest.changePowerTo({power}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    toggleEco: () ->
      @device.rest.toggleEco({},global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeProgramTo: (program) ->
      @device.rest.changeProgramTo({program}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeTemperatureTo: (temperatureSetpoint) ->
      @input.spinbox('disable')
      @device.rest.changeTemperatureTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input.spinbox('enable') )

    changeTemperatureLowTo: (temperatureSetpoint) ->
      @input2.spinbox('disable')
      @device.rest.changeTemperatureLowTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input2.spinbox('enable') )

    changeTemperatureHighTo: (temperatureSetpoint) ->
      @input3.spinbox('disable')
      @device.rest.changeTemperatureHighTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input3.spinbox('enable') )


  # register the item-class
  pimatic.templateClasses['led-light'] = LedLightItem
  pimatic.templateClasses['light-rgbct'] = LightRGBCTItem
  pimatic.templateClasses['dummythermostat'] = DummyThermostatItem
