module.exports = {
  title: "pimatic-dummies device config schemas"
  DummyLedLight: {
    title: "DummyLedLight config options"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:{}
  }
  DummyLightRGBW: {
    title: "DummylightRGBW config options"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:{}
  }
  DummyThermostat: {
    title: "DummyThermostat config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      temperatureRoom:
        description: "The Pimatic device.temperature id for the thermostat room temperature"
        type: "string"
        required: true
      humidityRoom:
        description: "The Pimatic device.humidity id for the thermostat room humidity"
        type: "string"
        required: false
      temperatureOutdoor:
        description: "The Pimatic device.temperature id for the outdoor temperature"
        type: "string"
        required: false
      humidityOutdoor:
        description: "The Pimatic device.humidity id for the outdoor humidity"
        type: "string"
        required: false
      pid:
        description: "Enable the PID controller for heater and cooler"
        type: "boolean"
        required: false
      minThresholdCelsius:
        description: "supported minimum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 5
      maxThresholdCelsius:
        description: "supported maximum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 30
      thermostatTemperatureUnit:
        description: "The unit the device is set to by default"
        enum: ["C","F"]
        default: "C"
      bufferRangeCelsius:
        description: "Specifies the minimum offset between heat-cool setpoints in Celsius, if heatcool mode is supported"
        type: "number"
        default: 2
  }

}
