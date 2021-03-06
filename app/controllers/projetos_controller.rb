class ProjetosController < ApplicationController
  before_action :authenticate_usuario!
  before_filter :checa_autorizacao, :only => [:edit, :destroy, :update]

  # fix temporário devido a problemas de compatibilidade com o cancan
  def checa_autorizacao
    @projeto = Projeto.find params[:id]
    if !@projeto.autorizacao(current_user, params[:action])
      redirect_to projetos_path, notice: "Você não está autorizado a executar essa operação!"
      false
    end
    true
  end


  # GET /projetos
  # GET /projetos.json
  def index
    if params["tipo"] == "TODOS" || params["tipo"].nil?
      @tipo = "TODOS"
      if current_usuario.role == "admin"
        @projetos = Projeto.order(:super_projeto_id).group_by(&:super_projeto_id).except(nil)
      else
        @projetos = current_usuario.projetos.order(:super_projeto_id).group_by(&:super_projeto_id).except(nil)
      end
    elsif params["tipo"] == "sub_projetos"
      @tipo = "sub_projetos"
      if current_usuario.role == "admin"
        @projetos = Projeto.all.select{|proj| !proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      else
        @projetos = current_usuario.projetos_coordenados.
          select{|proj| !proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      end
    elsif params["tipo"] == "super_projetos"
      @tipo = "super_projetos"
      if current_usuario.role == "admin"
        @projetos = Projeto.all.select{|proj| proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      else
        @projetos = current_usuario.projetos_coordenados.
          select{|proj| proj.super_projeto.nil?}.map{|sup| [sup,[]]}
      end
    end
    @projeto = Projeto.new

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @projetos }
    end
  end

  # GET /projetos/1/edit
  def edit
    authorize! :read, Projeto
    @projeto = Projeto.find(params[:id])
    @filhos_for_select  = Projeto.where{super_projeto_id != nil and id != my{params[:id]}.to_i}.pluck(:nome, :id)
    @pais_for_select = Projeto.where(super_projeto_id: nil).where{id != my{params[:id]}.to_i}.pluck(:nome, :id)
    @eh_super_projeto = @projeto.super_projeto.blank?
    @usuarios = Usuario.order(nome: :asc).pluck(:nome, :id)
    @hoje = Date.today
    @permissoes = Permissao.order(nome: :desc).pluck(:nome, :id)
  end

  def show
    authorize! :read, Projeto
    @hoje = Date.today
    @inicio = params[:inicio].blank? ? @hoje.beginning_of_month : (Date.parse(params[:inicio]))
    @fim = params[:fim].blank? ? @hoje.end_of_month : (Date.parse(params[:fim]))
    @projeto = Projeto.find(params[:id])
    @filhos_for_select  = Projeto.all.sort{ |projeto|
      @projeto.sub_projetos.include?(projeto) ? -1 : 1}.
        reject{|projeto| projeto == @projeto}.
          map{|filho| [filho.nome, filho.id]}
    @pais_for_select = Projeto.where(super_projeto_id: nil).
      sort{|a, b| a.nome <=> b.nome}.
        reject{|projeto| projeto == @projeto}.
          map{|proj| [proj.nome, proj.id]}
    @eh_super_projeto = @projeto.super_projeto.blank?
    @usuarios = Usuario.all.order(nome: :asc).collect {|u| [u.nome, u.id]}
    @ausencias = Ausencia.joins(:dia).where(dia: {data: @hoje.beginning_of_month..@hoje.end_of_month},
      projeto_id: @projeto.id).group_by{|x| x.dia.data}
    @equipe = @projeto.workons.joins(:usuario).where(:mostrar_ausencia => true)
    @atividades = Atividade.joins(:dia).where(dia: {data: @inicio..@fim}, projeto_id: @projeto.id).
      group_by{|x| x.dia.data}
    @permissoes = Permissao.order(nome: :desc).collect{|p| [p.nome, p.id]}
    @tab = params[:tab]
  end

  # POST /projetos
  # POST /projetos.json
  def create
    authorize! :create, Projeto
    @projeto = Projeto.new(projetos_params)
    if @projeto.save
      Workon.new(usuario: current_user, projeto: @projeto, permissao: Permissao.find_by(nome: "admin")).save
      redirect_to projetos_path, notice: I18n.t("projetos.create.success")
    else
      puts @projeto.errors
      flash[:errors] = I18n.t("projetos.create.failure")
      redirect_to projetos_path
    end
  end

  # PATCH /projetos/1
  # PATCH /projetos/1.json
  def update
    @projeto = Projeto.find(params[:id])
    authorize! :update, Projeto
    boards = @projeto.boards.to_a
    #lidar com boards
    unless params[:trello].blank?
      params[:trello].each do |id|
        repetido = false
        boards.each_with_index do |c, i|
          if id == c.board_id
            repetido = true
            boards.delete_at i
          end
        end
        unless repetido
          board = Board.new
          board.projeto = @projeto
          board.board_id = id
          board.save
        end
      end
    end
    unless params[:dados].blank?
      params[:dados].each do |campo_id, valor|
        dado = Dado.find_or_create_by(campo_id: campo_id, usuario_id: current_user.id)
        dado.valor = valor
        dado.save
      end
    end
    boards.each do |b|
      b.destroy
    end
    #lidar com subprojetos
    failure = false
    if params[:super_projeto] == "true"
      params[:sub_projetos].each do |index, sub|
        subprojeto = Projeto.find(sub["id"].to_i)
        if sub["filho"].nil? && subprojeto.super_projeto_id == @projeto.id
          failure ||= !(subprojeto.update super_projeto_id: nil)
        elsif !(sub["filho"].nil?)
          if !subprojeto.sub_projetos.blank?
            return (redirect_to :back, :alert => I18n.t("projetos.update.cant_be_sub", projeto_nome: subprojeto.nome ))
          else
            failure ||= !(subprojeto.update super_projeto_id: @projeto.id)
          end
        end
      end
      @projeto.update super_projeto_id: nil
    else
      @projeto.sub_projetos.each{|sub| sub.update super_projeto_id: nil}
    end
    failure ||= !(@projeto.update (projetos_params))
    @projeto.update super_projeto_id: nil if params[:super_projeto] == "true"
    respond_to do |format|
      if !failure
        format.html { redirect_to edit_projeto_path(@projeto), notice: I18n.t("projetos.update.success") }
        format.json { head :no_content }
      else
        format.html { redirect_to edit_projeto_path(@projeto), notice: I18n.t("projetos.update.failure") }
        format.json { render json: @projeto.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /projetos/1
  # DELETE /projetos/1.json
  def destroy
    authorize! :destroy, Projeto
    @projeto = Projeto.find(params[:id])
    @projeto.destroy
    respond_to do |format|
      format.html { redirect_to projetos_url }
      format.json { head :no_content }
    end
  end

  def campos_cadastro
    @projeto = Projeto.find params[:id]
    if((current_usuario.role == "admin") || (@projeto.admins_ids.include? current_usuario.id) )
      @projeto.campos.build if @projeto.campos.blank?
    else
      redirect_to :back, notice: "Você não está autorizado a executar essa operação"
    end
  end

  def atividades
    @projeto = Projeto.find(session[:id])
    @usuario = session[:usuario_id].nil? ? 0 : Usuario.find(session[:usuario_id])
    @usuários_select = @projeto.usuarios.map{|user| [user.nome, user.id]}
    @usuários_select.unshift([@usuario.nome, @usuario.id]) unless(session[:usuario_id].nil?)
    @aprovações = [["aprovada", "true"], ["reprovada","false"], ["não vista", "nil"]]
    @aprovações.unshift(@aprovações.select{|i| i[1] == session[:aprovacao]}.flatten)
    aprovacao = to_boolean session[:aprovacao]
    @inicio = (/^\d\d?\/\d\d?\/\d{2}\d{2}?$/ =~ session[:inicio]).nil? ? Date.today.beginning_of_month : Date.parse(session[:inicio])
    @fim = (/^\d\d?\/\d\d?\/\d{2}\d{2}?$/ =~ session[:fim]).nil? ? Date.today.end_of_month : Date.parse(session[:fim])
    @lista_atividades = @projeto.atividades.periodo(@inicio..@fim ).usuario(@usuario.id).aprovacao(aprovacao).limit(100)
     render "projetos/show/atividades"
  end

  def filtra_atividades
    session[:usuario_id] = params[:usuario_id]
    session[:id] = params[:id]
    session[:aprovacao] = params[:aprovacao]
    session[:fim] = params[:fim]
    session[:inicio] = params[:inicio]
    redirect_to atividades_projetos_path
  end

  private
    def projetos_params
      params.require(:projeto).permit(:ativo, :data_de_inicio, :descricao, :nome, :super_projeto_id,
        :tags_obrigatorio, :pai_obrigatorio,
        workons_attributes: [:id, :usuario_id, :permissao_id, :_destroy, :mostrar_ausencia, :data_inicio,
          {:coordenacoes => []}],
        sub_projetos: [:id, :filho],
        campos_attributes: [:id, :categoria, :nome, :tipo, :formato, :_destroy]
      )
    end

    def atividades_podem_ser_vistas_por?(usuario)
      (@projeto.autorizacao(usuario, "update") ||
        !((@projeto.workons.select{|z| z.coordenadores_ids.include? usuario.id}).blank?))
    end

end
