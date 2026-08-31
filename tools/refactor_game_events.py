
import re

with open("autoloads/GameEvents.gd", "r") as f:
    content = f.read()

new_sig = "signal powerful_shot_landed(shooter: HeavyPlayerController, speed: float, ratio: float)\n\n## Fired 0.3s before a predicted interception\nsignal anticipatory_turnover_predicted(team: int)"

content = content.replace("signal powerful_shot_landed(shooter: HeavyPlayerController, speed: float, ratio: float)", new_sig)

with open("autoloads/GameEvents.gd", "w") as f:
    f.write(content)

