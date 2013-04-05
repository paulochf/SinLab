class Dia < ActiveRecord::Base
  attr_accessible :entrada, :intervalo, :mes_id, :numero, :saida, :usuario_id

  belongs_to :usuario
  belongs_to :mes
	has_many :atividades
	accepts_nested_attributes_for :atividades

  validates :numero, :uniqueness => {:scope => :mes_id}

  def horas
    ((saida - entrada) - intervalo) / 3600
  end

  def formata_horas
    hora = (((saida - entrada) - intervalo) / 3600).to_i
    minuto = ((((saida - entrada) - intervalo) % 3600) / 60).to_i
    hora.to_s.rjust(2, '0') + ":" + minuto.to_s.rjust(2, '0')
  end

  def formata_intervalo
    hora = (intervalo / 3600).to_i
    minuto = (( intervalo % 3600) / 60).to_i
    hora.to_s.rjust(2, '0') + ":" + minuto.to_s.rjust(2, '0')
  end 

	def bar_width
		width = horas.nil? ? "0" : horas.to_s
		width + "%"
	end
end
