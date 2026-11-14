#!/usr/bin/env python3
"""Apply the exported dictation preferences through its supported CLI."""
import json
import pathlib
import subprocess

settings = json.loads((pathlib.Path(__file__).resolve().parent / 'desktop/superwhisper.json').read_text())


def call(*arguments):
    subprocess.run(['superwhisper', *arguments], check=True)


call('models', 'select', settings['processing'])
for key, value in settings['general'].items():
    if key == 'linux':
        for nested, preference in value.items():
            call('general', 'set', 'linux.' + nested, json.dumps(preference))
    else:
        call('general', 'set', key, json.dumps(value))
for key, value in settings['audio'].items():
    if key not in ('enableSilenceRemoval', 'useDefaultInputDevice'):
        call('audio', 'set', key, json.dumps(value))
call('audio', 'select', '')
call('audio', 'set', 'keepMicrophoneReady', json.dumps(settings['keepMicrophoneReady']))
for key, value in settings['shortcuts'].items():
    call('shortcuts', 'set', key, value or 'none')

call('vocab', 'auto', 'on' if settings['autoVocabularyCapture'] else 'off')
