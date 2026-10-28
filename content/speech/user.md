# what just happened

{{ happening }}

# where you are

{% for line in readout %}
{{ line }}
{% endfor %}

# earlier on this crossing

{% for line in recent %}
- {{ line }}
{% else %}
- Nothing yet.
{% endfor %}

# what you are asking for

{% if ask %}
Hands on {{ ask }}.
{% else %}
Nothing in particular.
{% endif %}
