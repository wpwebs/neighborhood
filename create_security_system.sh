#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0 [HOME_ADDRESS] NEIGHBOR1 [NEIGHBOR2 ...]"
  echo "  HOME_ADDRESS: (optional) The home address number (default is 3592)."
  echo "  NEIGHBOR: The address numbers of the neighbors."
}

usage

# Home address number with default value of 3592
HOME_ADDRESS=${1:-3592}
shift

# Neighbors' address numbers are link
NEIGHBORS=("$@")

# Paths to the configuration files
BOOLEAN_HELPERS_PATH="../boolean_helpers.yaml"
DATETIME_HELPERS_PATH="../datetime_helpers.yaml"
BUTTON_HELPERS_PATH="../button_helpers.yaml"
TIMER_HELPERS_PATH="../timer_helpers.yaml"

AUTOMATION_PATH="../automations.yaml"
LOVELACE_CONFIG_PATH="/config/ui-lovelace.yaml"

# Create datetime helpers to define Alarm Start/End Time
cat <<EOL >> ${DATETIME_HELPERS_PATH}
  ${HOME_ADDRESS}_alarm_start_time:
    name: ${HOME_ADDRESS} Alarm Start Time
    has_date: false
    has_time: true
    initial: '01:00:00'
  ${HOME_ADDRESS}_alarm_end_time:
    name: ${HOME_ADDRESS} Alarm End Time
    has_date: false
    has_time: true
    initial: '05:00:00'
EOL

# Create timer helpers to define how long the alarm activate
cat <<EOL >> ${TIMER_HELPERS_PATH}
  ${HOME_ADDRESS}_alarm_timer:
    name: Alarm Timer
    duration: '00:00:20'
EOL

# Create boolean helpers to enable/disable the alarm
cat <<EOL >> ${BOOLEAN_HELPERS_PATH}
  ${HOME_ADDRESS}_alarm_enable:
    name: Enable Alarm System
    initial: on
EOL

# Create boolean helpers to link neighbors
for NEIGHBOR in "${NEIGHBORS[@]}"; do
  cat <<EOL >> ${BOOLEAN_HELPERS_PATH}
  ${HOME_ADDRESS}_neighbor_${NEIGHBOR}_link:
    name: ${HOME_ADDRESS} link to ${NEIGHBOR} 
    initial: on
EOL
done

# Create button helpers to allow manual activation of the alarm
cat <<EOL >> ${BUTTON_HELPERS_PATH}
  ${HOME_ADDRESS}_activate_alarm:
    name: Hold to Activate alarm
EOL

# Create automations
cat <<EOL >> ${AUTOMATION_PATH}
- id: ${HOME_ADDRESS}_activate
  alias: ${HOME_ADDRESS}_activate
  description: Activate neighborhood alarm based on relay trigger at ${HOME_ADDRESS}
  mode: parallel
  trigger:
    - platform: state
      entity_id:
      - input_boolean.${HOME_ADDRESS}_alarm_enable
      to: 'off'
      id: disable_alarm
    - platform: state
      entity_id:
        - binary_sensor.${HOME_ADDRESS}_alarm_relay
      to: "on"
      id: alarm_triggered_by_sensor
    - platform: state
      entity_id:
      - input_button.${HOME_ADDRESS}_activate_alarm
      to:
      for:
        seconds: 2
      id: hold_to_activate_alarm
    - platform: event
      event_type: timer.finished
      event_data:
        entity_id: timer.${HOME_ADDRESS}_alarm_timer
      id: alarm_timer_finished
  condition:
    - condition: time
      after: input_datetime.${HOME_ADDRESS}_alarm_start_time
      before: input_datetime.${HOME_ADDRESS}_alarm_end_time
  action:
  - choose:
    - conditions:
      - condition: trigger
        id: 
          - disable_alarm
          - alarm_timer_finished
      sequence:
      - service: switch.turn_off
        target:
          entity_id:
          - switch.${HOME_ADDRESS}_alarm
EOL

# Add actions for neighbors' alarm
for NEIGHBOR in "${NEIGHBORS[@]}"; do
  cat <<EOL >> ${AUTOMATION_PATH}
          - switch.${NEIGHBOR}_alarm
EOL
done

cat <<EOL >> ${AUTOMATION_PATH}
        data: {}
    - conditions:
      - condition: state
        entity_id: input_boolean.${HOME_ADDRESS}_alarm_enable
        state: 'on'
      - condition: trigger
        id:
        - hold_to_activate_alarm
        - alarm_triggered_by_sensor
      sequence:
      - service: switch.turn_on
        target:
          entity_id: switch.${HOME_ADDRESS}_alarm
        data: {}
      - choose:
EOL

# Add actions for neighbors if linked
for NEIGHBOR in "${NEIGHBORS[@]}"; do
  cat <<EOL >> ${AUTOMATION_PATH}
        - conditions:
          - condition: state
            entity_id: input_boolean.${HOME_ADDRESS}_neighbor_${NEIGHBOR}_link
            state: 'on'
          sequence:
          - service: switch.turn_on
            target:
              entity_id: switch.${NEIGHBOR}_alarm
            data: {}
EOL
done

# Define the new view dashboard
VIEW_CONFIG=$(cat <<EOL
  - title: '${HOME_ADDRESS}'
    visible:
      - user: '${HOME_ADDRESS}'
    cards:
      - type: vertical-stack
        title: ${HOME_ADDRESS} Neighborhood Security System
        cards:
          - type: entities
            entities:
              - entity: input_boolean.${HOME_ADDRESS}_alarm_enable
            state_color: true
          - type: entities
            entities:
              - entity: input_datetime.${HOME_ADDRESS}_alarm_start_time
              - entity: input_datetime.${HOME_ADDRESS}_alarm_end_time
          - type: entities
            entities:
EOL
)

for NEIGHBOR in "${NEIGHBORS[@]}"; do
  VIEW_CONFIG+="
              - entity: input_boolean.${HOME_ADDRESS}_neighbor_${NEIGHBOR}_link"
done

VIEW_CONFIG+="
            title: Neighbors are included
            show_header_toggle: false
            state_color: true
          - type: custom:mushroom-entity-card
            entity: input_button.${HOME_ADDRESS}_activate_alarm
            tap_action:
              action: none
            hold_action:
              action: call-service
              service: input_button.press
              target:
                entity_id: input_button.${HOME_ADDRESS}_activate_alarm
            double_tap_action:
              action: none
            fill_container: false
            icon_color: red
    path: '${HOME_ADDRESS}'
"
# Append the new view configuration to the Dashboard
echo "$VIEW_CONFIG" >> "$LOVELACE_CONFIG_PATH"

echo "New view added to the Home Assistant Dashboard for home address ${HOME_ADDRESS}."

echo "Files updated:
- $BOOLEAN_HELPERS_PATH
- $DATETIME_HELPERS_PATH
- $BUTTON_HELPERS_PATH
- $TIMER_HELPERS_PATH
- $AUTOMATION_PATH
- $LOVELACE_CONFIG_PATH"