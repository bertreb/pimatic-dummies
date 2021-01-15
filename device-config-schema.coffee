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
  DummyAlarmPanel: {
    title: "DummyAlarmPanel config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:{
      pin:
        description: "The pincode for disarming the alarm"
        type: "string"
      triggerHome:
        description: "The Pimatic device id of the alarm trigger in ArmHome state"
        type: "string"
      triggerAway:
        description: "The Pimatic device id of the alarm trigger in ArmAway state"
        type: "string"
      triggerNight:
        description: "The Pimatic device id of the alarm trigger in ArmNight state"
        type: "string"
        required: false
      armTime:
        description: "The time (in seconds) before the AlarmPanel goes to Armed"
        type: "number"
        default: 30
      disarmTime:
        description: "The time (in seconds) before the AlarmPanel goes to Disarmed"
        type: "number"
        default: 30
      pendingTime:
        description: "The time (in seconds) after a trigger the alarm goes to Triggered"
        type: "number"
        default: 30
    }
  }
}
