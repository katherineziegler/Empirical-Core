import React, {Component} from 'react'
import { connect } from 'react-redux';
import _ from 'lodash'
import {hashToCollection} from '../../../libs/hashToCollection'

class ShowClassroomLesson extends Component<any, any> {
  constructor(props){
    super(props);
    this.state = {
      editions: {},
      sort: 'last_published_at',
      direction: 'dsc'
    }
  }

  componentWillMount() {
    this.getEditions(this.props)
  }

  componentWillReceiveProps(nextProps) {
    if (nextProps.customize.editions && Object.keys(nextProps.customize.editions).length > 0) {
      if (Object.keys(this.state.editions).length === 0) {
        this.getEditions(nextProps)
      } else if (!_.isEqual(this.props.customize.editions, nextProps.customize.editions)) {
        this.getEditions(nextProps)
      }
    }
  }

  getEditions(props) {
    const classroomLessonID = props.params.classroomLessonID
    const allEditions = props.customize.editions
    if (allEditions && Object.keys(allEditions).length > 0) {
      const lessonEditions = {}
      const editionIds = Object.keys(allEditions)
      editionIds.forEach(id => {
        const edition = allEditions[id]
        if (edition.lesson_id === classroomLessonID) {
          lessonEditions[id] = edition
        }
      })
      this.setState({editions: lessonEditions})
    }
  }

  sortData(data) {
    switch (this.state.sort) {
      case 'name':
        return this.sortAlphabetically(data);
      case 'last_published_at':
      case 'user_id':
        return this.sortNumerically(data)
    }
  }

  sortNumerically(data) {
    console.log(data)
    console.log(this.state.sort)
    return data.sort((a, b) => {
      const aSort = a[this.state.sort] ? a[this.state.sort] : 0
      const bSort = b[this.state.sort] ? b[this.state.sort] : 0
      return aSort - bSort
    })
  }

  sortAlphabetically(data) {
    return data.sort((a, b,) => {
      const aSort = a[this.state.sort] ? a[this.state.sort] : 'No Name'
      const bSort = b[this.state.sort] ? b[this.state.sort] : 'No Name'
      return aSort.localeCompare(bSort)
    })
  }

  clickSort(sort) {
    let direction = 'dsc';
    if (this.state.sort === sort) {
      direction = this.state.direction === 'dsc' ? 'asc' : 'dsc';
    }
    this.setState({
      sort, direction,
    });
  }

  classroomLesson() {
    return this.props.classroomLessons.data[this.props.params.classroomLessonID]
  }

  renderEditionTable() {
    if (Object.keys(this.state.editions).length > 1) {
      return <table className="table is-striped is-bordered">
      <thead>
      <tr>
      <th onClick={this.clickSort.bind(this, 'user_id')}>User ID</th>
      <th onClick={this.clickSort.bind(this, 'name')}>Name</th>
      <th onClick={this.clickSort.bind(this, 'last_published_at')}>Last Published At</th>
      </tr>
      </thead>
      <tbody>
      {this.renderEditionRows()}
      </tbody>
      </table>
    }
  }

  renderEditionRows() {
    const data = hashToCollection(this.state.editions)
    const sorted = this.sortData(data)
    const directed = this.state.direction === 'dsc' ? sorted.reverse() : sorted;
    return _.map(directed, edition => {
      const link = `#/teach/class-lessons/${edition.lesson_id}/preview/${edition.key}`
      const date = edition.last_published_at ? `${new Date(edition.last_published_at)}` : 'Not Published'
      return <tr key={edition.key}>
      <td>{edition.user_id}</td>
      <td><a href={link}>{edition.name || 'No Name'}</a></td>
      <td>{date}</td>
      </tr>
    }
    );
  }

  renderMessage() {
    if (Object.keys(this.state.editions).length === 0) {
      return <p>No editions have been created for this lesson.</p>
    }
  }

  render() {
    if (this.props.classroomLessons.hasreceiveddata) {
      const classroomLessonID = this.props.params.classroomLessonID
      return (
        <div className="admin-classroom-lessons-container">
          <div className="lesson-header">
            <h4 className="title is-4">{this.classroomLesson().title} <a target="_blank" href={`/#/teach/class-lessons/${classroomLessonID}/preview`}>Preview</a> </h4>
          </div>
          {this.renderEditionTable()}
          {this.renderMessage()}
        </div>
      )
    } else {
      return <h1>Loading</h1>
    }
  }

}

function select(props) {
  return {
    classroomLessons: props.classroomLessons,
    classroomLessonsReviews: props.classroomLessonsReviews,
    customize: props.customize
  };
}

export default connect(select)(ShowClassroomLesson)
